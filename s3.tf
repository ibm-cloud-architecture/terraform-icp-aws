# configuration backup s3 bucket
resource "aws_s3_bucket" "icp_config_backup" {
  bucket        = "icpbackup-${random_id.clusterid.hex}"
  acl           = "private"
  force_destroy = true # Set to false to keep the backup even if we do a terraform destroy

  tags =
    "${merge(
      var.default_tags,
      map("Name", "icp-backup-${random_id.clusterid.hex}"),
      map("icp_instance", var.instance_name ))}"
}

# upload scripts to config backup bucket
resource "aws_s3_bucket_object" "bootstrap" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/bootstrap.sh"
  source = "${path.module}/scripts/bootstrap.sh"
}

resource "aws_s3_bucket_object" "create_client_cert" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/create_client_cert.sh"
  source = "${path.module}/scripts/create_client_cert.sh"
}

resource "aws_s3_bucket_object" "functions" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/functions.sh"
  source = "${path.module}/scripts/functions.sh"
}

resource "aws_s3_bucket_object" "start_install" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/start_install.sh"
  source = "${path.module}/scripts/start_install.sh"
}

# lock down bucket access to just my VPC and terraform user
resource "aws_s3_bucket_policy" "icp_config_backup_policy_allow_vpc" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  policy =<<POLICY
{
  "Version": "2012-10-17",
  "Id": "icp_config_backup_vpc-${random_id.clusterid.hex}",
  "Statement": [
     {
       "Sid": "Access-to-terraform-user",
       "Action": "s3:*",
       "Effect": "Allow",
       "Resource": ["${aws_s3_bucket.icp_config_backup.arn}",
                    "${aws_s3_bucket.icp_config_backup.arn}/*"],
       "Principal": {
         "AWS": [
           "${data.aws_caller_identity.current.arn}"
         ]
       }
     },
     {
       "Sid": "Access-to-icp-vpc",
       "Action": "s3:*",
       "Effect": "Allow",
       "Resource": ["${aws_s3_bucket.icp_config_backup.arn}",
                    "${aws_s3_bucket.icp_config_backup.arn}/*"],
       "Principal": "*",
       "Condition": {
         "StringEquals": {
           "aws:sourceVpc": "${aws_vpc.icp_vpc.id}"
         }
       }
     }
   ]
}
POLICY
}