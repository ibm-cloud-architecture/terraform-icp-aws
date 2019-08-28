#!/bin/bash

source /tmp/icp_scripts/functions.sh

while getopts ":b:i:k:" arg; do
    case "${arg}" in
      b)
        s3_lambda_bucket=${OPTARG}
        ;;
      i)
        inception_image=${OPTARG}
        ;;
      k)
        kube_master=${OPTARG}
        ;;
    esac
done

parse_icpversion ${inception_image}
echo "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"

sudo docker run \
  -e LICENSE=accept \
  --net=host \
  -v /usr/local/bin:/data \
  ${registry}${registry:+/}${org}/${repo}:${tag} \
  cp /usr/local/bin/kubectl /data

/usr/local/bin/kubectl config set-cluster local --server=https://${kube_master}:8001 --insecure-skip-tls-verify=true
/usr/local/bin/kubectl config set-credentials user --embed-certs=true --client-certificate=/opt/ibm/cluster/cfc-certs/kubernetes/kubecfg.crt --client-key=/opt/ibm/cluster/cfc-certs/kubernetes/kubecfg.key
/usr/local/bin/kubectl config set-context ctx --cluster=local --user=user --namespace=kube-system
/usr/local/bin/kubectl config use-context ctx

/usr/local/bin/kubectl create clusterrolebinding lambda-role --clusterrole=cluster-admin --user=lambda --group=lambda
/usr/local/bin/kubectl -n default apply -f /tmp/icp_scripts/asg-configmap.yaml

openssl genrsa -out /tmp/lambda-key.pem 4096
openssl req -new -key /tmp/lambda-key.pem -out /tmp/lambda-cert.csr -subj '/O=lambda/CN=lambda'
openssl x509 -req -days 3650 -sha256 -in /tmp/lambda-cert.csr -CA /opt/ibm/cluster/cfc-certs/root-ca/ca.crt -CAkey /opt/ibm/cluster/cfc-certs/root-ca/ca.key -set_serial 2 -out /tmp/lambda-cert.pem

/usr/local/bin/aws s3 cp /tmp/lambda-cert.pem s3://${s3_lambda_bucket}/lambda-cert.pem
/usr/local/bin/aws s3 cp /tmp/lambda-key.pem s3://${s3_lambda_bucket}/lambda-key.pem
/usr/local/bin/aws s3 cp /opt/ibm/cluster/cfc-certs/root-ca/ca.crt s3://${s3_lambda_bucket}/ca.crt

cat <<EOF > ~/kuberc
export PATH=$PATH:/usr/local/bin
kubectl config set-cluster local --server=https://${kube_master}:8001 --insecure-skip-tls-verify=true
kubectl config set-credentials user --embed-certs=true --client-certificate=/opt/ibm/cluster/cfc-certs/kubernetes/kubecfg.crt --client-key=/opt/ibm/cluster/cfc-certs/kubernetes/kubecfg.key
kubectl config set-context ctx --cluster=local --user=user --namespace=kube-system
kubectl config use-context ctx
EOF

/usr/local/bin/kubectl get secret infra-registry-key -o yaml | grep -v annotations | grep -v last-applied-configuration | grep -v creationTimestamp | grep -v namespace | grep -v resourceVersion | grep -v uid | /usr/local/bin/kubectl -n default apply -f -

/usr/local/bin/kubectl -n default patch serviceaccount default -p '{"imagePullSecrets": [{"name": "infra-registry-key"}]}'

/usr/local/bin/kubectl -n kube-system apply -f /tmp/icp_scripts/cluster-autoscaler-rbac.yaml

/usr/local/bin/kubectl -n kube-system apply -f /tmp/icp_scripts/cluster-autoscaler-deployment.yaml

# Cluster autoscaler recommends running same version as kube version, however CA versions only started to sync with kube version starting with 1.12.x
# this command below should manage earlier versions of kube
KUBE_VERSION=$(/usr/local/bin/kubectl version -o json | python -c "import sys, json; print json.load(sys.stdin)['serverVersion']['gitVersion'].split('+')[0].replace('v1.11.','v1.3.').replace('v1.10.','v1.2.').replace('v1.9.','v1.1.').replace('v1.8.','v1.0.')")

/usr/local/bin/kubectl -n kube-system set image deployment/cluster-autoscaler cluster-autoscaler=k8s.gcr.io/cluster-autoscaler:${KUBE_VERSION}

