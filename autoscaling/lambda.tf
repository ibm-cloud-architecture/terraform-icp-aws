locals  {
  iam_lambda_role_arn = "${var.existing_lambda_iam_instance_profile_name != "" ?
        element(concat(data.aws_iam_role.icp_lambda_iam_role.*.arn, list("")), 0) :
        element(concat(aws_iam_role.icp_lambda_iam_role.*.arn, list("")), 0)}"
}

data "aws_iam_role" "icp_lambda_iam_role" {
  count = "${var.enabled && var.existing_lambda_iam_instance_profile_name != "" ? 1 : 0}"
  name = "${var.existing_lambda_iam_instance_profile_name}"
}

data "archive_file" "lambda_function" {
  count = "${var.enabled ? 1 : 0}"
  type              = "zip"
  output_path       = "${path.module}/lambda.zip"
  source_dir       = "${path.module}/lambda"
}

resource "aws_lambda_permission" "icp_scale_up_cloudwatch" {
  count = "${var.enabled ? 1 : 0}"
  statement_id = "icp-scale-up-cloudwatch-${var.cluster_id}"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.icp_autoscale.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.icp_worker_node_added_event.arn}"

  depends_on = [ "aws_lambda_function.icp_autoscale"]
}

resource "aws_lambda_permission" "icp_scale_down_cloudwatch" {
  count = "${var.enabled ? 1 : 0}"
  statement_id = "icp-scale-down-cloudwatch-${var.cluster_id}"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.icp_autoscale.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.icp_worker_node_remove_event.arn}"

  depends_on = [ "aws_lambda_function.icp_autoscale"]
}

resource "aws_lambda_function" "icp_autoscale" {
  count            = "${var.enabled ? 1 : 0}"
  depends_on       = ["aws_s3_bucket_object.icp_lambda_function"]

  s3_bucket        = "${var.lambda_s3_bucket}"
  s3_key           = "icp-autoscale.zip"
  function_name    = "icp-worker-autoscale-${var.cluster_id}"
  role             = "${local.iam_lambda_role_arn}"
  handler          = "index.handler"
  runtime          = "nodejs8.10"
  timeout          = 10

  vpc_config {
    subnet_ids = ["${var.private_subnet_ids}"]
    security_group_ids = ["${var.security_groups}"]
  }

  environment {
    variables = {
      kube_api_url   = "${var.kube_api_url}"
      kube_namespace = "default"
      kube_token     = ""
      s3_bucket      = "${var.lambda_s3_bucket}"
    }
  }
}

resource "aws_iam_instance_profile" "icp_lambda_instance_profile" {
  count = "${var.enabled && var.existing_lambda_iam_instance_profile_name == "" ? 1 : 0}"
  name = "${var.lambda_iam_role_name}-instance-profile-${var.cluster_id}"
  role = "${aws_iam_role.icp_lambda_iam_role.name}"
}
