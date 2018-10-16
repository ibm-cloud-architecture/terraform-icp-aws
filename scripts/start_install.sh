#!/bin/bash

source /tmp/icp_scripts/functions.sh

##### MAIN #####
while getopts ":s:c:i:r:" arg; do
  case "${arg}" in
    s)
      s3_patch_scripts=${OPTARG}
      ;;
    c)
      s3_config_bucket=${OPTARG}
      ;;
    i)
      inception_image=${OPTARG}
      ;;
    r)
      s3_registry_bucket=${OPTARG}
      ;;
  esac
done

awscli=/usr/local/bin/aws

# Figure out the version
# This will populate $org $repo and $tag
parse_icpversion ${inception_image}
echo "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"

if [ ! -z "${username}" -a ! -z "${password}" ]; then
  echo "logging in to ${registry} ..."
  until docker login ${registry} -u ${username} -p ${password}; do
    sleep 1
  done
fi

inception_image=${registry}${registry:+/}${org}/${repo}:${tag}

# create the cluster directory and merge the custom config
docker run \
  -e LICENSE=accept \
  -v /opt/ibm:/data ${inception_image} \
  cp -r cluster /data

# pull down the config items
${awscli} s3 cp s3://${s3_config_bucket}/hosts /opt/ibm/cluster/hosts
${awscli} s3 cp s3://${s3_config_bucket}/cfc-certs /opt/ibm/cluster/cfc-certs
${awscli} s3 cp s3://${s3_config_bucket}/ssh_key /opt/ibm/cluster/ssh_key
${awscli} s3 cp s3://${s3_config_bucket}/icp-terraform-config.yaml /tmp/icp-terraform-config.yaml

# HOTFIX for https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.0/troubleshoot/manifest_tool.html
echo "Symlinking manifest-tool into /usr/bin"
sudo ln -s /usr/local/bin/manifest-tool /usr/bin/manifest-tool

# append the image repo
if [ ! -z "${registry}${registry:+}" ]; then
  echo "image_repo: ${registry}${registry:+/}${org}" >> /tmp/icp-terraform-config.yaml
fi

# append private registry user, password if we detect it
if [ ! -z "${username}" ]; then
  echo "docker_username: ${username}" >> /tmp/icp-terraform-config.yaml
  echo "docker_password: ${password}" >> /tmp/icp-terraform-config.yaml
  echo "private_registry_enabled: true" >> /tmp/icp-terraform-config.yaml
  echo "private_registry_server: ${registry}${registry:+}" >> /tmp/icp-terraform-config.yaml
fi

# merge config
python - <<EOF
import os, sys, yaml, json, getpass
ci = '/tmp/icp-terraform-config.yaml'
co = '/opt/ibm/cluster/config.yaml'

# Load config items if provided
with open(ci, 'r') as stream:
  config_i = yaml.load(stream)

with open(co, 'r') as stream:
  try:
    config_o = yaml.load(stream)
  except yaml.YAMLError as exc:
    print(exc)

# Second accept any changes from supplied config items
config_o.update(config_i)

# Automatically add the ansible_become if it does not exist, and if we are not root
if not 'ansible_user' in config_o and getpass.getuser() != 'root':
  config_o['ansible_user'] = getpass.getuser()
  config_o['ansible_become'] = True

# to handle terraform bug regarding booleans, find strings "true" or "false"
# and convert them to booleans
new_config = {}
for key, value in config_o.iteritems():
  if type(value) is str or type(value) is unicode:
    if value.lower() == 'true':
      new_config[key] = True
    elif value.lower() == 'false':
      new_config[key] = False
    else:
      new_config[key] = value
    continue
  new_config[key] = value

# Write the new configuration
with open(co, 'w') as of:
  yaml.safe_dump(new_config, of, explicit_start=True, default_flow_style = False)
EOF

chmod 400 /opt/ibm/cluster/ssh_key

# find my IP address, which will be on the interface the default route is configured on
myip=`ip route get 8.8.8.8 | awk 'NR==1 {print $NF}'`

# wait for all hosts in the cluster to finish cloud-init
docker run \
  -e ANSIBLE_HOST_KEY_CHECKING=false \
  -v /opt/ibm/cluster:/installer/cluster \
  --entrypoint ansible \
  --net=host \
  -t \
  ${inception_image} \
  -i /installer/cluster/hosts all:\!${myip} \
  --private-key /installer/cluster/ssh_key \
  -u icpdeploy \
  -b \
  -m wait_for \
  -a "path=/var/lib/cloud/instance/boot-finished timeout=18000"

# kick off the installer
docker run \
  -e LICENSE=accept \
  --net=host \
  -t \
  -v /opt/ibm/cluster:/installer/cluster \
  ${inception_image} \
  install

# if additional post-install scripts specified, run the scripts through the installer now
for script in ${s3_patch_scripts}; do
  echo "Executing post-install patch script ${script} ..."
  script_name=`basename ${script}`
  ${awscli} s3 cp ${script} /opt/ibm/cluster/${script_name}
  chmod +x /opt/ibm/cluster/${script_name}
  docker run -e LICENSE=accept -t --net=host -v /opt/ibm/cluster:/installer/cluster ${inception_image} ./cluster/${script_name}
  rm -f /opt/ibm/cluster/${script_name}
done

# REVERTED BACK TO EBS-BASED REGISTRY SUPPORT IN ICP 3.1.0
# patch the registry to use our S3 bucket
#region=`curl http://169.254.169.254/latest/dynamic/instance-identity/document | grep "region" | awk -F: '{print $2}' | sed -e 's/[ ",]//g'`
#sed -i '/filesystem/{$!{N;s/filesystem:\n\(.*\)rootdirectory.*/s3:\n\1bucket: '${s3_registry_bucket}'\n\1region: '${region}'/}}' /opt/ibm/cluster/cfc-components/registry-conf/registry-config.yaml
#kubectl="docker run --net=host -e KUBECONFIG=/tmp/kubeconfig.yaml -v /opt/ibm/cluster:/installer/cluster -v /tmp:/tmp --entrypoint /usr/local/bin/kubectl ${inception_image}"
#$kubectl config set-cluster local --server=https://localhost:8001 --insecure-skip-tls-verify=true
#$kubectl config set-credentials user --embed-certs=true --client-certificate=/installer/cluster/cfc-certs/kubecfg.crt --client-key=/installer/cluster/cfc-certs/kubecfg.key
#$kubectl config set-context ctx --cluster=local --user=user --namespace=kube-system
#$kubectl config use-context ctx
#$kubectl delete configmap registry-config
#$kubectl create configmap registry-config --from-file=/installer/cluster/cfc-components/registry-conf/registry-config.yaml
#$kubectl delete pods -l app=image-manager
#rm -f /tmp/kubeconfig.yaml

# backup the config
${awscli} s3 sync /opt/ibm/cluster s3://${s3_config_bucket}
