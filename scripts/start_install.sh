#!/bin/bash

source /tmp/icp_scripts/functions.sh

logfile="/tmp/icp_logs/start_install.log"

#
# Function for logging output.
#
logmsg() {
  hostname=`hostname`;
  date=`date +"%m-%d-%y %r"`;
  echo $date $hostname $1 | tee -a $logfile
}

#
# This function will populate the local Docker repository with the ICP images.
#
image_load() {
  if [[ ! -z $(docker images -q ${inception_image}) ]]; then
    # If we don't have an image locally we'll pull from docker hub registry
    logmsg "Not required to load images. Exiting"
    return 0
  fi

  if [[ ! -z "${image_location}" ]]; then
    # Decide which protocol to use
    if [[ "${image_location:0:2}" == "s3" ]]; then
      # stream it right out of s3 into docker
      logmsg "Copying binary package from ${image_location} ..."
      ${awscli} s3 cp ${image_location} /tmp 

      logmsg "Loading docker images from /tmp/`basename ${image_location}` ..."
      tar zxf /tmp/`basename ${image_location}` -O | docker load | tee -a $logfile

      logmsg "Copying binary package to /opt/ibm/cluster/images ..."
      mkdir -p /opt/ibm/cluster/images
      mv /tmp/`basename ${image_location}` /opt/ibm/cluster/images

      logmsg "Completed loading docker images from ${image_location} ..."
    fi
  fi
}


logmsg "~~~~~~~~ Starting ICP installation Code ~~~~~~~~"

##### MAIN #####
while getopts ":b:i:c:" arg; do
    case "${arg}" in
      b)
        s3_config_bucket=${OPTARG}
        ;;
      i)
        inception_image=${OPTARG}
        ;;
      c)
        image_location=${OPTARG}
        ;;
    esac
done

export awscli=`which aws`
if [ -z "${awscli}" ]; then
  export awscli="/usr/local/aws/bin/aws"
fi

if ! docker --version; then
  logmsg "Docker is not installed."
  exit 1
fi

# Figure out the version
# This will populate $org $repo and $tag
parse_icpversion ${inception_image}
logmsg "Populating the registry."
logmsg "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"

if [ ! -z "${username}" -a ! -z "${password}" ]; then
  logmsg "logging in to ${registry} ..."
  until docker login ${registry} -u ${username} -p ${password}; do
    sleep 1
  done
fi

# load images
image_load

inception_image=${registry}${registry:+/}${org}/${repo}:${tag}

logmsg "Pulling terraform-module-icp-deploy"
if [ ! -d /tmp/icp-deploy ]; then
  mkdir -p /tmp/icp-deploy
fi

docker pull hashicorp/terraform:light

cd /tmp/icp-deploy
docker run -v `pwd`:/deploy -w=/deploy --entrypoint=git hashicorp/terraform:light clone https://github.com/ibm-cloud-architecture/terraform-module-icp-deploy.git
docker run -v `pwd`:/deploy -w=/deploy/terraform-module-icp-deploy --entrypoint=git hashicorp/terraform:light checkout 3.1.1

# write the terraform.tfvars
${awscli} s3 cp s3://${s3_config_bucket}/terraform.tfvars terraform-module-icp-deploy/terraform.tfvars

# write the additional icp config file for merging
${awscli} s3 cp s3://${s3_config_bucket}/icp-terraform-config.yaml terraform-module-icp-deploy/icp-terraform-config.yaml

docker run -v `pwd`:/deploy -w=/deploy/terraform-module-icp-deploy hashicorp/terraform:light init
docker run -v `pwd`:/deploy -w=/deploy/terraform-module-icp-deploy hashicorp/terraform:light apply -auto-approve

# backup the config
logmsg "Backing up the config to the S3 bucket."
${awscli} s3 sync /opt/ibm/cluster s3://${s3_config_bucket}

logmsg "~~~~~~~~ Completed ICP installation Code ~~~~~~~~"
