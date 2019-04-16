####### AWS Access and Region Details #############################
variable "aws_region" {
  default  = "us-east-2"
  description = "One of us-east-2, us-east-1, us-west-1, us-west-2, ap-south-1, ap-northeast-2, ap-southeast-1, ap-southeast-2, ap-northeast-1, us-west-2, eu-central-1, eu-west-1, eu-west-2, sa-east-1"
}

variable "azs" {
  type  = "list"
  description = "The availability zone letter appendix you want to deploy to in the selected region "
  default = ["a", "b", "c"]
}

####### AWS Deployment Details ####################################
# SSH Key
variable "key_name" {
  description = "Name of the EC2 key pair"
}

variable "privatekey" {
  type = "string"
  description = "base64 encoded private key file contents"
  default = ""
}

variable "ssh_user" {
  default = "ec2-user"
  description = "Most Ubuntu AMIs use Ubuntu as the default user. Normally safe to leave"
}

# Default tags to apply to resources
variable "default_tags" {
  type    = "map"
  default = {
    Owner         = "icpuser"
    Environment   = "icp-test"
  }

}
# VPC Details
variable "vpcname" { default = "icp-vpc" }
variable "cidr" { default = "10.10.0.0/16" }

# Subnet Details
variable "subnetname" { default = "icp-subnet" }
variable "subnet_cidrs" {
  description = "List of subnet CIDRs"
  type        = "list"
  default     = ["10.10.10.0/24", "10.10.11.0/24", "10.10.12.0/24" ]
}

variable "pub_subnet_cidrs" {
  description = "List of subnet CIDRs"
  type        = "list"
  default     = ["10.10.20.0/24", "10.10.21.0/24", "10.10.22.0/24" ]
}

variable "ec2_iam_role_name" { default = "icp-ec2-iam" }
variable "private_domain" { default = "icp-cluster.icp" }

variable "ami" { default = "" }

# EC2 instances
# no bastion host by default.  set to 1 if you want to debug
variable "bastion" {
  type = "map"
  default = {
    nodes     = "0"
    type      = "t2.micro"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "10" //GB
  }
}

variable "master" {
  type = "map"
  default = {
    nodes     = "3"
    type      = "m4.xlarge"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "100" //GB
    docker_vol = "100" // GB
    ebs_optimized = true    // not all instance types support EBS optimized
  }
}
variable "proxy" {
  type = "map"
  default = {
    nodes     = "3"
    type      = "m4.large"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "100" //GB
    docker_vol = "100" // GB
    ebs_optimized = true    // not all instance types support EBS optimized
  }
}

variable "management" {
  type = "map"
  default = {
    nodes     = "3"
    type      = "m4.xlarge"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "100" //GB
    docker_vol = "100" // GB
    ebs_optimized = true    // not all instance types support EBS optimized
  }
}

variable "worker" {
  type = "map"
  default = {
    nodes     = "3"
    type      = "m4.xlarge"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "100" //GB
    docker_vol = "100" // GB
    ebs_optimized = true    // not all instance types support EBS optimized
  }
}

variable "va" {
  type = "map"
  default = {
    nodes     = "3"
    type      = "m4.xlarge"
    ami       = "" // Leave blank to let terraform search for Ubuntu 16.04 ami. NOT RECOMMENDED FOR PRODUCTION
    disk      = "100" //GB
    docker_vol = "100" // GB
    ebs_optimized = true    // not all instance types support EBS optimized
  }
}

variable "instance_name" { default = "icp" }
variable "icppassword" { default = "MySecretP4ssw0RD" }

variable "docker_package_location" {
  description = "When installing ICP EE on RedHat. Prefix location string with http: or nfs: to indicate protocol "
  default     = ""
}

variable "image_location" {
  description = "Image location when installing EnterPrise edition. prefix location string with http: or nfs: to indicate protocol"
  default     = ""
}

variable "patch_images" {
  description = "Additional patch images loaded before install, stored in S3"
  type        = "list"
  default     = []
}

variable "patch_scripts" {
  description = "Additional patch scripts run after install, stored in S3"
  type        = "list"
  default     = []
}

variable "icp_inception_image" {
  description = "icp-inception bootstrap image repository"
  default     = "ibmcom/icp-inception:2.1.0.3-ee"
}

variable "icp_config_yaml" {
  default     = "./icp-config.yaml"
}

variable "icp_network_cidr" {
  default     = "192.168.0.0/16"
}

variable "icp_service_network_cidr" {
  default     = "172.16.0.0/24"
}

variable "postinstallbackup" {
  description = "Change to True to perform backup of /opt/ibm/cluster on boot master after completed installation"
  default     = "true"
}

variable "existing_ec2_iam_instance_profile_name" {
  description = "Existing IAM instance profile name to apply to EC2 instances"
  default     = ""
}

variable "existing_lambda_iam_instance_profile_name" {
  description = "Existing IAM instance profile name to apply to Lambda functions"
  default     = ""
}

variable "user_provided_cert_dns" {
  description = "User provided certificate DNS"
  default     = ""
}

variable "enable_autoscaling" {
  default = false
}

variable "allowed_cidr_master_8001" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_master_8443" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_master_8500" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_master_8600" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_proxy_80" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_proxy_443" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "allowed_cidr_bastion_22" {
  type = "list"
  default = [
    "0.0.0.0/0"
  ]
}

variable "use_aws_cloudprovider" {
  default = "true"
}
