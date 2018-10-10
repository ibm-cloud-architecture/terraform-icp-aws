/* Default security group */
resource "aws_security_group" "default" {
  name = "icp_default_sg-${random_id.clusterid.hex}"
  description = "Default security group that allows inbound and outbound traffic from all instances in the VPC"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.icp_vpc.cidr_block}"]
    self        = true
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-default-sg-${random_id.clusterid.hex}"),
    map("kubernetes.io/cluster/${random_id.clusterid.hex}", "${random_id.clusterid.hex}")
  )}"
}

resource "aws_security_group_rule" "bastion-22-ingress" {
  count = "${var.bastion["nodes"] > 0 ? length(var.allowed_cidr_bastion_22) : 0}"
  type = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_bastion_22, count.index)}"
  ]
  security_group_id = "${aws_security_group.bastion.id}"
}

resource "aws_security_group_rule" "bastion-22-egress" {
  count = "${var.bastion["nodes"] > 0 ? 1 : 0}"
  type = "egress"
  from_port   = "0"
  to_port     = "0"
  protocol    = "-1"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.bastion.id}"
}

resource "aws_security_group" "bastion" {
  count = "${var.bastion["nodes"] > 0 ? 1 : 0}"
  name = "icp-bastion-${random_id.clusterid.hex}"
  description = "allow SSH"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-bastion-${random_id.clusterid.hex}")
  )}"
}

resource "aws_security_group_rule" "proxy-80-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.proxy.id}"
    description = "allow icp to contact itself on console endpoint over the nat gateway"
}

resource "aws_security_group_rule" "proxy-80-ingress" {
  count = "${length(var.allowed_cidr_proxy_80)}"
  type = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_proxy_80, count.index)}"
  ]
  security_group_id = "${aws_security_group.proxy.id}"
}

resource "aws_security_group" "proxy" {
  name = "icp-proxy-${random_id.clusterid.hex}"
  description = "ICP ${random_id.clusterid.hex} proxy nodes"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-proxy-${random_id.clusterid.hex}")
  )}"
}

resource "aws_security_group_rule" "proxy-443-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.proxy.id}"
    description = "allow icp to contact itself on console endpoint over the nat gateway"
}

resource "aws_security_group_rule" "proxy-443-ingress" {
  count = "${length(var.allowed_cidr_proxy_443)}"
  type = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_proxy_443, count.index)}"
  ]
  security_group_id = "${aws_security_group.proxy.id}"
}

resource "aws_security_group_rule" "proxy-egress" {
  type = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.proxy.id}"
}

resource "aws_security_group_rule" "master-8443-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.master.id}"
    description = "allow icp to contact itself on console endpoint over the nat gateway"
}

resource "aws_security_group_rule" "master-8443-ingress" {
  count = "${length(var.allowed_cidr_master_8443)}"
  type = "ingress"
  from_port   = 8443
  to_port     = 8443
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_master_8443, count.index)}"
  ]
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "master-8001-ingress" {
  count = "${length(var.allowed_cidr_master_8001)}"
  type = "ingress"
  from_port   = 8001
  to_port     = 8001
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_master_8001, count.index)}"
  ]
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "master-8001-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.master.id}"
    description = "allow icp to contact its kubernetes API over nat gateway"
}

resource "aws_security_group_rule" "master-8500-ingress" {
  count = "${length(var.allowed_cidr_master_8500)}"
  type = "ingress"
  from_port   = 8500
  to_port     = 8500
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_master_8500, count.index)}"
  ]
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "master-8500-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.master.id}"
    description = "allow icp to contact itself on registry endpoint over the nat gateway"
}

resource "aws_security_group_rule" "master-8600-ingress" {
  count = "${length(var.allowed_cidr_master_8600)}"
  type = "ingress"
  from_port   = 8600
  to_port     = 8600
  protocol    = "tcp"
  cidr_blocks = [
    "${element(var.allowed_cidr_master_8600, count.index)}"
  ]
  security_group_id = "${aws_security_group.master.id}"
}

resource "aws_security_group_rule" "master-8600-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 8600
    to_port     = 8600
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.master.id}"
    description = "allow icp to contact itself on registry endpoint over the nat gateway"
}

resource "aws_security_group" "master" {
  name = "icp-master-${random_id.clusterid.hex}"
  description = "ICP ${random_id.clusterid.hex} master nodes"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-master-${random_id.clusterid.hex}")
  )}"
}

resource "aws_security_group_rule" "master-9443-ngw" {
    count = "${length(var.azs)}"
    type = "ingress"
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = ["${element(aws_eip.icp_ngw_eip.*.public_ip, count.index)}/32"]
    security_group_id = "${aws_security_group.master.id}"
    description = "allow icp to contact itself on oidc endpoint over the nat gateway"
}

resource "aws_security_group_rule" "master-egress" {
  type = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.master.id}"
}


resource "aws_security_group" "icp-registry-mount" {
  count = "${var.master["nodes"] > 1 ? 1 : 0 }"
  name = "icp_efs_registry_sg-${random_id.clusterid.hex}"
  description = "allow incoming to EFS from master nodes"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [ "${aws_security_group.default.id}"]
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [ "${aws_security_group.default.id}"]
    self        = true
  }

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-registry-mount-sg-${random_id.clusterid.hex}")
  )}"
}

resource "aws_security_group" "icp-audit-mount" {
  count = "${var.master["nodes"] > 1 ? 1 : 0 }"
  name = "icp_efs_audit_sg-${random_id.clusterid.hex}"
  description = "allow incoming to EFS from master nodes"
  vpc_id = "${aws_vpc.icp_vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [
      "${aws_security_group.default.id}"
    ]
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [
      "${aws_security_group.default.id}"
    ]
    self        = true
  }

  tags = "${merge(
    var.default_tags,
    map("Name", "icp-audit-mount-sg-${random_id.clusterid.hex}")
  )}"
}

