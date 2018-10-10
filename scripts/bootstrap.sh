#!/bin/bash

ubuntu_install(){
  # attempt to retry apt-get update until cloud-init gives up the apt lock
  until apt-get update; do
    sleep 2
  done

  until apt-get install -y \
    unzip \
    python \
    python-yaml \
    thin-provisioning-tools \
    nfs-client \
    lvm2; do
    sleep 2
  done
}

crlinux_install() {
  until yum install -y \
    unzip \
    PyYAML \
    device-mapper \
    libseccomp \
    libtool-ltdl \
    libcgroup \
    iptables \
    device-mapper-persistent-data \
    nfs-utils \
    lvm2; do
    sleep 2
  done
}

awscli=/usr/local/bin/aws

docker_install() {
  echo "Install docker from ${package_location}"
  sourcedir=/tmp/icp-docker

  if docker --version; then
    echo "Docker already installed. Exiting"
    return 0
  fi

  # Figure out if we're asked to install at all
  if [[ ! -z ${package_location} ]]; then
    mkdir -p ${sourcedir}

    # Decide which protocol to use
    if [[ "${package_location:0:2}" == "s3" ]]
    then
      # Figure out what we should name the file
      filename="icp-docker.bin"
      /usr/local/bin/aws s3 cp ${package_location} ${sourcedir}/${filename}
      package_file="${sourcedir}/${filename}"
    fi

    chmod a+x ${package_file}
    ${package_file} --install
  elif [[ "${OSLEVEL}" == "ubuntu" ]]; then
    # if we're on ubuntu, we can install docker-ce off of the repo
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

    add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"

    apt-get update && apt-get install -y docker-ce
  fi

  partprobe
  lsblk

  systemctl enable docker
  storage_driver=`docker info | grep 'Storage Driver:' | cut -d: -f2 | sed -e 's/\s//g'`
  echo "storage driver is ${storage_driver}"
  if [ "${storage_driver}" == "devicemapper" ]; then
    systemctl stop docker

    # remove storage-driver from docker cmdline
    sed -i -e '/ExecStart/ s/--storage-driver=devicemapper//g' /usr/lib/systemd/system/docker.service

    # docker installer uses devicemapper already; switch to overlay2
    cat > /tmp/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    mv /tmp/daemon.json /etc/docker/daemon.json

    systemctl daemon-reload
  fi

  if [ ! -z "${docker_disk}" ]; then
    echo "Setting up ${docker_disk} and mounting at /var/lib/docker ..."
    systemctl stop docker

    sudo mv /var/lib/docker /var/lib/docker.bk
    sudo mkdir -p /var/lib/docker
    sudo parted -s -a optimal ${docker_disk} mklabel gpt -- mkpart primary xfs 1 -1

    sudo partprobe

    sudo mkfs.xfs -n ftype=1 ${docker_disk}1
    echo "${docker_disk}1  /var/lib/docker   xfs  defaults   0 0" | sudo tee -a /etc/fstab
    sudo mount -a

    sudo mv /var/lib/docker.bk/* /var/lib/docker
    rm -rf /var/lib/docker.bk
    systemctl start docker
  fi

  # docker takes a while to start because it needs to prepare the
  # direct-lvm device ... loop here until it's running
  _count=0
  systemctl is-active docker | while read line; do
    if [ ${line} == "active" ]; then
      break
    fi

    echo "Docker is not active yet; waiting 3 seconds"
    sleep 3
    _count=$((_count+1))

    if [ ${_count} -gt 10 ]; then
      echo "Docker not active after 30 seconds"
      return 1
    fi
  done

  echo "Docker is installed."
  docker info
}

image_load() {
  if [[ ! -z $(docker images -q ${inception_image}) ]]; then
    # If we don't have an image locally we'll pull from docker hub registry
    echo "Not required to load images. Exiting"
    return 0
  fi

  if [[ ! -z "${image_location}" ]]; then
    if [[ "${image_location:0:2}" == "s3" ]]; then
      echo "Load docker images from ${image_location} ..."
      #TODO Is this install directory parameterized?
      IMAGE_DIR=/opt/ibm/cluster/images
      mkdir -p ${IMAGE_DIR}
      ${awscli} s3 cp ${image_location} ${IMAGE_DIR}/ibm-cloud-private-x86_64-3.1.0.tar.gz 
      tar zxf ${IMAGE_DIR}/ibm-cloud-private-x86_64-3.1.0.tar.gz -O | docker load
    fi
  fi

  # if additional patches specified, load the images now
  for img in `echo "${s3_patch_images}"`; do
    echo "Load docker images from ${img} ..."
    if echo ${img} | grep 'tar$'; then
      ${awscli} s3 cp ${img} - | docker load
    elif echo ${img} | grep 't.*gz$'; then
      ${awscli} s3 cp ${img} - | tar zxf - -O | docker load
    fi
  done
}

##### MAIN #####
while getopts ":a:p:d:i:s:" arg; do
    case "${arg}" in
      a)
        s3_patch_images=${OPTARG}
        ;;
      p)
        package_location=${OPTARG}
        ;;
      d)
        docker_disk=${OPTARG}
        ;;
      i)
        image_location=${OPTARG}
        ;;
      s)
        inception_image=${OPTARG}
        ;;
    esac
done


#Find Linux Distro
if grep -q -i ubuntu /etc/*release; then
  OSLEVEL=ubuntu
else
  OSLEVEL=other
fi
echo "Operating System is $OSLEVEL"

# pre-reqs
if [ "$OSLEVEL" == "ubuntu" ]; then
  ubuntu_install
else
  crlinux_install
fi

docker_install
image_load

echo "Complete.."
