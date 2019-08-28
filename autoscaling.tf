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
    docker_registry = "${var.user_provided_cert_dns != "" ? var.user_provided_cert_dns : aws_lb.icp-console.dns_name}:8500"

    aws_region            = "${var.aws_region}"
    azs                   = ["${var.azs}"]
    ami                   = "${var.worker["ami"] != "" ? var.worker["ami"] : local.default_ami }"
    worker_root_disk_size = "${var.worker["disk"]}"
    worker_docker_vol_size = "${var.worker["docker_vol"]}"
    key_name              = "${var.key_name}"
    instance_type         = "${var.worker["type"]}"
    ebs_optimized         = "${var.worker["ebs_optimized"]}"
    instance_name         = "${var.instance_name}"
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
    icp_config_s3_bucket      = "${aws_s3_bucket.icp_config_backup.id}"
    asg_tags                  = ["${data.null_data_source.asg-tags.*.outputs}"]
}

data "null_data_source" "asg-tags" {
  count = "${length(keys(var.default_tags))}"
  inputs = {
    key                 = "${element(keys(var.default_tags), count.index)}"
    value               = "${element(values(var.default_tags), count.index)}"
    propagate_at_launch = "true"
  }
}

resource "aws_s3_bucket_object" "icp_cluster_autoscaler_yaml" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/cluster-autoscaler-deployment.yaml"
  content = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
        - image: k8s.gcr.io/cluster-autoscaler:v1.2.2
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --skip-nodes-with-system-pods=false
            - --expander=least-waste
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,kubernetes.io/cluster/${random_id.clusterid.hex}
            - --balance-similar-node-groups=true
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          imagePullPolicy: "Always"
      nodeSelector:
        master: "true"
      tolerations:
      - effect: NoSchedule
        key: dedicated
        operator: Exists
      - key: CriticalAddonsOnly
        operator: Exists
      volumes:
        - name: ssl-certs
          hostPath:
            path: "/etc/ssl/certs/ca-bundle.crt"
EOF
}

resource "aws_s3_bucket_object" "asg_configmap" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/asg-configmap.yaml"
  source = "${path.module}/scripts/asg-configmap.yaml"
}

resource "aws_s3_bucket_object" "cluster_autoscaler_rbac_yaml" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "scripts/cluster-autoscaler-rbac.yaml"
  source = "${path.module}/scripts/cluster-autoscaler-rbac.yaml"
}

