resource "aws_launch_configuration" "icp_worker_lc" {
  count = "${var.enabled ? 1 : 0}"
  name          = "icp-workers-${var.cluster_id}"
  image_id      = "${var.ami}"
  key_name      = "${var.key_name}"
  instance_type = "${var.instance_type}"

  iam_instance_profile = "${var.ec2_iam_instance_profile_id}"
  associate_public_ip_address = false

  security_groups = ["${var.security_groups}"]

  ebs_optimized = "${var.ebs_optimized}"
  root_block_device {
    volume_size = "${var.worker_root_disk_size}"
  }

  # docker direct-lvm volume
  ebs_block_device {
    device_name       = "/dev/xvdx"
    volume_size       = "${var.worker_docker_vol_size}"
    volume_type       = "gp2"
  }

  user_data = <<EOF
#cloud-config
packages:
  - unzip
  - python
  - bind-utils
rh_subscription:
  enable-repo: rhui-REGION-rhel-server-optional
write_files:
  - path: /tmp/bootstrap-node.sh
    permissions: '0755'
    encoding: b64
    content: ${base64encode(file("${path.module}/../scripts/bootstrap-node.sh"))}
runcmd:
  - /tmp/bootstrap-node.sh -c ${var.icp_config_s3_bucket} -s "bootstrap.sh"
  - /tmp/icp_scripts/bootstrap.sh ${var.docker_package_location != "" ? "-p ${var.docker_package_location}" : "" } -d /dev/xvdx ${var.image_location != "" ? "-i ${var.image_location}" : "" } -s ${var.icp_inception_image}
users:
  - default
  - name: icpdeploy
    groups: [ wheel ]
    sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
    shell: /bin/bash
    ssh-authorized-keys:
    - ${var.icp_pub_key}
manage_resolv_conf: true
resolv_conf:
  nameservers: [ ${cidrhost(element(var.private_subnet_cidr, count.index), 2)}]
  domain: ${var.cluster_id}.${var.private_domain}
  searchdomains:
  - ${var.cluster_id}.${var.private_domain}
EOF
}

resource "aws_autoscaling_group" "icp_worker_asg" {
  count = "${length(var.azs)}"
  name                 = "icp-worker-asg-${var.aws_region}${element(var.azs, count.index)}-${var.cluster_id}"
  launch_configuration = "${aws_launch_configuration.icp_worker_lc.name}"
  min_size             = 0
  max_size             = 20
  force_delete         = true

  vpc_zone_identifier  = ["${element(var.private_subnet_ids, count.index)}"]

  tags = ["${concat(
    var.asg_tags,
    list(map("key", "k8s.io/cluster-autoscaler/enabled", "value", "${var.enabled}", "propagate_at_launch", "false")),
    list(map("key", "kubernetes.io/cluster/${var.cluster_id}", "value", "${var.cluster_id}", "propagate_at_launch", "true"))
  )}"]
}

resource "aws_autoscaling_lifecycle_hook" "icp_add_worker_hook" {
  count = "${length(var.azs)}"
  name                   = "icp-workernode-added-${var.aws_region}${element(var.azs, count.index)}-${var.cluster_id}"
  autoscaling_group_name = "${element(aws_autoscaling_group.icp_worker_asg.*.name, count.index)}"
  default_result         = "ABANDON"
  heartbeat_timeout      = 3600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"

  notification_metadata = <<EOF
{
  "icp_inception_image": "${var.docker_registry}/${var.icp_inception_image}",
  "docker_package_location": "${var.docker_package_location}",
  "image_location": "${var.image_location}",
  "cluster_backup": "icpbackup-${var.cluster_id}",
  "cluster_id": "${var.cluster_id}",
  "instance_name": "${var.instance_name}"
}
EOF
}

resource "aws_autoscaling_lifecycle_hook" "icp_del_worker_hook" {
  count = "${length(var.azs)}"
  name                   = "icp-workernode-removed-${var.aws_region}${element(var.azs, count.index)}-${var.cluster_id}"
  autoscaling_group_name = "${element(aws_autoscaling_group.icp_worker_asg.*.name, count.index)}"
  default_result         = "ABANDON"
  heartbeat_timeout      = 3600
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

  notification_metadata = <<EOF
{
  "icp_inception_image": "${var.docker_registry}/${var.icp_inception_image}",
  "docker_package_location": "${var.docker_package_location}",
  "image_location": "${var.image_location}",
  "cluster_backup": "icpbackup-${var.cluster_id}",
  "cluster_id": "${var.cluster_id}",
  "instance_name": "${var.instance_name}"
}
EOF
}
