resource "aws_s3_bucket" "icp_lambda" {
  count         = "${var.enable_autoscaling ? 1 : 0}"
  bucket        = "icplambda-${random_id.clusterid.hex}"
  acl           = "private"
  force_destroy = true

  tags =
    "${merge(
      var.default_tags,
      map("Name", "icp-lambda-${random_id.clusterid.hex}"),
      map("icp_instance", var.instance_name )
    )}"
}

module "icpautoscaling" {
    enabled = "${var.enable_autoscaling}"

    source = "./autoscaling"

    ec2_iam_instance_profile_id = "${local.iam_ec2_node_instance_profile_id}"
    existing_lambda_iam_instance_profile_name = "${var.existing_lambda_iam_instance_profile_name}"
    cluster_id = "${random_id.clusterid.hex}"

    #icpuser         = "aws_lb_target_group_attachment.master-8001.arn" // attempt at workaround for missing depends on

    kube_api_url    = "https://${aws_lb.icp-console.dns_name}:8001"

    aws_region            = "${var.aws_region}"
    azs                   = ["${var.azs}"]
    ami                   = "${var.worker["ami"] != "" ? var.worker["ami"] : local.default_ami }"
    worker_root_disk_size = "${var.worker["disk"]}"
    worker_docker_vol_size = "${var.worker["docker_vol"]}"
    key_name              = "${var.key_name}"
    instance_type         = "${var.worker["type"]}"
    security_groups = [
      "${aws_security_group.default.id}"
    ]
    private_domain = "${var.private_domain}"
    private_subnet_cidr = "${aws_subnet.icp_private_subnet.*.cidr_block}"
    private_subnet_ids = "${aws_subnet.icp_private_subnet.*.id}"
    icp_pub_key = "${tls_private_key.installkey.public_key_openssh}"

    docker_package_location   = "${local.docker_package_uri}"
    image_location            = "${local.image_package_uri}"
    icp_inception_image       = "${var.icp_inception_image}"
    lambda_s3_bucket          = "${local.lambda_s3_bucket}"
}
