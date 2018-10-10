resource "aws_efs_file_system" "icp-registry" {
  count = "${var.master["nodes"] > 1 ? 1 : 0 }"
  creation_token = "icp-${random_id.clusterid.hex}-registry"
  tags = "${merge(
    var.default_tags,
    map("Name", "icp-registry")
  )}"
}

resource "aws_efs_mount_target" "icp-registry" {
  count = "${var.master["nodes"] > 1 ? var.master["nodes"] : 0 }"
  file_system_id = "${aws_efs_file_system.icp-registry.id}"
  subnet_id     = "${element(aws_subnet.icp_private_subnet.*.id, count.index)}"
  security_groups = [ "${aws_security_group.icp-registry-mount.id}"]
}

resource "aws_efs_file_system" "icp-audit" {
  count = "${var.master["nodes"] > 1 ? 1 : 0 }"
  creation_token = "icp-${random_id.clusterid.hex}-audit"
  tags = "${merge(
    var.default_tags,
    map("Name", "icp-audit")
  )}"
}

resource "aws_efs_mount_target" "icp-audit" {
  count = "${var.master["nodes"] > 1 ? var.master["nodes"] : 0 }"
  file_system_id = "${aws_efs_file_system.icp-audit.id}"
  subnet_id     = "${element(aws_subnet.icp_private_subnet.*.id, count.index)}"
  security_groups = [ "${aws_security_group.icp-audit-mount.id}"]
}
