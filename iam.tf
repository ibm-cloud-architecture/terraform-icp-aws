resource "aws_iam_role" "icp_ec2_iam_master_role" {
  count = "${var.existing_ec2_iam_master_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_master_role_name}-${random_id.clusterid.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "icp_ec2_iam_master_role_policy" {
  count = "${var.existing_ec2_iam_master_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_master_role_name}-policy-${random_id.clusterid.hex}"
  role = "${aws_iam_role.icp_ec2_iam_master_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:CompleteLifecycleAction",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyVolume",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DetachVolume",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeVpcs",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:AttachLoadBalancerToSubnets",
        "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:ConfigureHealthCheck",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancerListeners",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DetachLoadBalancerFromSubnets",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancerPolicies",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
        "iam:CreateServiceLinkedRole",
        "kms:DescribeKey"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "icp_ec2_iam_node_role" {
  count = "${var.existing_ec2_iam_node_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_node_role_name}-${random_id.clusterid.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "icp_ec2_iam_node_role_policy" {
  count = "${var.existing_ec2_iam_node_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_node_role_name}-policy-${random_id.clusterid.hex}"
  role = "${aws_iam_role.icp_ec2_iam_node_role.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeRegions",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        } 
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "icp_iam_s3fullaccess" {
  count = "${var.existing_ec2_iam_master_instance_profile_name == "" ? 1 : 0}"
  role = "${aws_iam_role.icp_ec2_iam_master_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "icp_ec2_master_instance_profile" {
  count = "${var.existing_ec2_iam_master_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_master_role_name}-instance-profile-${random_id.clusterid.hex}"
  role = "${aws_iam_role.icp_ec2_iam_master_role.name}"
}

resource "aws_iam_instance_profile" "icp_ec2_node_instance_profile" {
  count = "${var.existing_ec2_iam_node_instance_profile_name == "" ? 1 : 0}"
  name = "${var.ec2_iam_node_role_name}-instance-profile-${random_id.clusterid.hex}"
  role = "${aws_iam_role.icp_ec2_iam_node_role.name}"
}
