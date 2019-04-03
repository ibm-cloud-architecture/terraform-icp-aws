variable "existing_lambda_iam_instance_profile_name" {
  description = "Existing IAM instance profile name to apply to Lambda functions"
  default     = ""
}


variable "ec2_iam_instance_profile_id" {
  description = "IAM instance profile name to apply to EC2 instances"
  default     = ""
}

variable "lambda_iam_role_name" {
  default = "icp-lambda-iam"
}

variable "ami" {
  default = ""
}

variable "key_name" {
  default = ""
}

variable "instance_type" {
  default = ""
}

variable "cluster_id" {
  default = ""
}

variable "kube_api_url" {
  default = ""
}

variable "security_groups" {
  default = []
}

variable "private_subnet_cidr" {
  default = []
}

variable "private_subnet_ids" {
  default = []
}

variable "private_domain" {
  default = ""
}

variable "icp_pub_key" {
  default = ""
}

variable "worker_root_disk_size" {
  default = "100"
}

variable "worker_docker_vol_size" {
  default = "100"
}

variable "aws_region" {
  default = ""
}

variable "azs" {
  default = []
}

variable "docker_package_location" {
  description = "When installing ICP EE on RedHat. Prefix location string with http: or nfs: to indicate protocol "
  default     = ""
}

variable "image_location" {
  description = "Image location when installing EnterPrise edition. prefix location string with http: or nfs: to indicate protocol"
  default     = ""
}

variable "icp_inception_image" {
  description = "icp-inception bootstrap image repository"
  default     = "ibmcom/icp-inception:2.1.0.2-ee"
}

variable "lambda_s3_bucket" {
  default = ""
}

variable "enabled" {
  default = true
}
