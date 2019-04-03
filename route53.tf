resource "aws_route53_zone" "icp_private" {
  name = "${random_id.clusterid.hex}.${var.private_domain}"
  vpc {
    vpc_id = "${aws_vpc.icp_vpc.id}"
  }
  force_destroy = "true"
}

resource "aws_route53_record" "master" {
  // same number of records as instances
  count         = "${var.master["nodes"]}"
  zone_id       = "${aws_route53_zone.icp_private.zone_id}"
  name = "${format("${var.instance_name}-master%02d", count.index + 1) }"
  type = "A"
  ttl = "300"
  // matches up record N to instance N
  records = ["${element(aws_instance.icpmaster.*.private_ip, count.index)}"]
}

resource "aws_route53_record" "proxy" {
  // same number of records as instances
  count         = "${var.proxy["nodes"]}"
  zone_id       = "${aws_route53_zone.icp_private.zone_id}"
  name = "${format("${var.instance_name}-proxy%02d", count.index + 1) }"
  type = "A"
  ttl = "300"
  // matches up record N to instance N
  records = ["${element(aws_instance.icpproxy.*.private_ip, count.index)}"]
}

resource "aws_route53_record" "management" {
  // same number of records as instances
  count         = "${var.management["nodes"]}"
  zone_id       = "${aws_route53_zone.icp_private.zone_id}"
  name = "${format("${var.instance_name}-management%02d", count.index + 1) }"
  type = "A"
  ttl = "300"
  // matches up record N to instance N
  records = ["${element(aws_instance.icpmanagement.*.private_ip, count.index)}"]
}

resource "aws_route53_record" "va" {
  // same number of records as instances
  count         = "${var.va["nodes"]}"
  zone_id       = "${aws_route53_zone.icp_private.zone_id}"
  name = "${format("${var.instance_name}-va%02d", count.index + 1) }"
  type = "A"
  ttl = "300"
  // matches up record N to instance N
  records = ["${element(aws_instance.icpva.*.private_ip, count.index)}"]
}

resource "aws_route53_record" "worker" {
  // same number of records as instances
  count         = "${var.worker["nodes"]}"
  zone_id       = "${aws_route53_zone.icp_private.zone_id}"
  name = "${format("${var.instance_name}-worker%02d", count.index + 1) }"
  type = "A"
  ttl = "300"
  // matches up record N to instance N
  records = ["${element(aws_instance.icpnodes.*.private_ip, count.index)}"]
}
