## You must set a key file name to be able to ssh to any of the created VMs
# key_name = "<name of your ssh key>"

image_location = ""

ami = "ubuntu"         # Use Ubuntu to simplify Docker installation on simple PoC

icp_inception_image = "ibmcom/icp-inception:3.2.0"

bastion = {
 nodes = "1"
}

master = {
  nodes = "1"          # required to be '1' to install CE
  type = "m4.2xlarge"  # or m4.4xlarge if 'management' nodes=0
  disk = "300"
}

management = {
  nodes = "1"          # or optionally 0 if you want to run all platform services on 'master'
  type = "m4.xlarge"
  disk = "300"
}

va = {
  nodes = "0"
}

proxy = {
  nodes = "1"          # required to be '1' to install CE
  disk = "150"
}
