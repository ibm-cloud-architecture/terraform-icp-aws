resource "aws_cloudwatch_event_rule" "icp_worker_node_added_event" {
  count = "${var.enabled ? 1 : 0}"
  name        = "icp-worker-asg-node-added-${var.cluster_id}"
  description = "Trigger when autoscaling group adds node"

  event_pattern = <<EOF
{
  "detail-type": [
    "EC2 Instance-launch Lifecycle Action"
  ],
  "source": [
    "aws.autoscaling"
  ],
  "detail": {
    "AutoScalingGroupName": [
      ${join(",", formatlist("\"%v\"", aws_autoscaling_group.icp_worker_asg.*.name))}
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_rule" "icp_worker_node_remove_event" {
  count = "${var.enabled ? 1 : 0}"
  name        = "icp-worker-asg-node-remove-${var.cluster_id}"
  description = "Trigger when autoscaling group removes node"

  event_pattern = <<EOF
{
  "detail-type": [
    "EC2 Instance-terminate Lifecycle Action"
  ],
  "source": [
    "aws.autoscaling"
  ],
  "detail": {
    "AutoScalingGroupName": [
      ${join(",", formatlist("\"%v\"", aws_autoscaling_group.icp_worker_asg.*.name))}
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "icp_lambda_add_node_target" {
  count = "${var.enabled ? 1 : 0}"
  rule      = "${aws_cloudwatch_event_rule.icp_worker_node_added_event.name}"
  target_id = "icp-scale-up-${var.cluster_id}"
  arn       = "${aws_lambda_function.icp_autoscale.arn}"
}

resource "aws_cloudwatch_event_target" "icp_lambda_remove_node_target" {
  count = "${var.enabled ? 1 : 0}"
  rule      = "${aws_cloudwatch_event_rule.icp_worker_node_remove_event.name}"
  target_id = "icp-scale-down-${var.cluster_id}"
  arn       = "${aws_lambda_function.icp_autoscale.arn}"
}
