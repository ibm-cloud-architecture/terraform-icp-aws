#!/bin/bash
logfile="/tmp/icp_logs/bootstrap.log"

# Create logs directory.
[ -d /tmp/icp_logs ] || mkdir /tmp/icp_logs

#
# Function for logging output.
#
logmsg() {
  hostname=`hostname`;
  date=`date +"%m-%d-%y %r"`;
  echo $date $hostname $1 | tee -a $logfile
}

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

#
# This function will install docker on the node.
#
docker_install() {
  logmsg "Checking docker install status."
  if docker --version; then
    logmsg "Docker already installed. Exiting"
    return 0
  fi

  # Figure out if we're asked to install at all
  if [[ ! -z ${docker_installer} ]]; then
    logmsg "Install docker from ${docker_installer}"
    sourcedir=/tmp/icp-docker

    mkdir -p ${sourcedir}

    # Decide which protocol to use
    if [[ "${docker_installer:0:2}" == "s3" ]]
    then
      # Figure out what we should name the file
      filename="icp-docker.bin"
      /usr/local/bin/aws s3 cp ${docker_installer} ${sourcedir}/${filename}
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
  logmsg "storage driver is ${storage_driver}"
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
    logmsg "Setting up ${docker_disk} and mounting at /var/lib/docker ..."
    systemctl stop docker

    sudo mv /var/lib/docker /var/lib/docker.bk
    sudo mkdir -p /var/lib/docker
    sudo parted -s -a optimal ${docker_disk} mklabel gpt -- mkpart primary xfs 1 -1

    sudo partprobe

    sudo mkfs.xfs -n ftype=1 ${docker_disk}1
    logmsg "${docker_disk}1  /var/lib/docker   xfs  defaults   0 0" | sudo tee -a /etc/fstab
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

    logmsg "Docker is not active yet; waiting 3 seconds"
    sleep 3
    _count=$((_count+1))

    if [ ${_count} -gt 10 ]; then
      logmsg "Docker not active after 30 seconds"
      return 1
    fi
  done

  logmsg "Docker is installed."
  docker info
}

logmsg "~~~~~~~~~~~~~ Bootstrap.sh starting. ~~~~~~~~~~~~~~~~"

##### MAIN #####
while getopts ":p:d:i:s:e:" arg; do
    case "${arg}" in
      p)
        docker_installer=${OPTARG}
        ;;
      d)
        docker_disk=${OPTARG}
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

# Install Docker
docker_install

logmsg "~~~~~~~~~~~~~ Bootstrap.sh complete. ~~~~~~~~~~~~~~~~"
