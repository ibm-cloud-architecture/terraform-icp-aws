locals {
    icppassword    = "${var.icppassword != "" ? "${var.icppassword}" : "${random_id.adminpassword.hex}"}"

    registry_server = "${var.registry_server != "" ? "${var.registry_server}" : "${var.instance_name}-${random_id.clusterid.hex}-cluster"}"
    namespace       = "${dirname(var.icp_inception_image)}" # This will typically return ibmcom

    # The final image repo will be either interpolated from what supplied in icp_inception_image or
    image_repo      = "${var.registry_server == "" ? "" : "${local.registry_server}/${local.namespace}"}"
    icp-version     = "${format("%s%s%s", "${local.docker_username != "" ? "${local.docker_username}:${local.docker_password}@" : ""}",
                        "${var.registry_server != "" ? "${var.registry_server}/" : ""}",
                        "${var.icp_inception_image}")}"

    # If we're using external registry we need to be supplied registry_username and registry_password
    docker_username = "${var.registry_username != "" ? var.registry_username : ""}"
    docker_password = "${var.registry_password != "" ? var.registry_password : ""}"

    # This is just to have a long list of disabled items to use in icp-deploy.tf
    disabled_list = "${list("disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled")}"

    disabled_management_services = "${zipmap(var.disabled_management_services, slice(local.disabled_list, 0, length(var.disabled_management_services)))}"

}

resource "random_id" "adminpassword" {
  byte_length = "16"
}

resource "aws_s3_bucket_object" "icp_cert_crt" {
  count = "${var.user_provided_cert_dns != "" ? 1 : 0}"
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "cfc-certs/icp-auth.crt"
  source = "${path.module}/cfc-certs/icp-auth.crt"
}

resource "aws_s3_bucket_object" "icp_cert_key" {
  count = "${var.user_provided_cert_dns != "" ? 1 : 0}"
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "cfc-certs/icp-auth.key"
  source = "${path.module}/cfc-certs/icp-auth.key"
}

resource "aws_s3_bucket_object" "icp_config_yaml" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "icp-terraform-config.yaml"
  content = <<EOF
management_services:
${join("\n", formatlist("  %v: disabled", var.disabled_management_services))}
EOF
}

resource "aws_s3_bucket_object" "terraform_tfvars" {
  bucket = "${aws_s3_bucket.icp_config_backup.id}"
  key    = "terraform.tfvars"
  content = <<EOF
boot-node = "${element(aws_network_interface.mastervip.*.private_ip, 0)}"
icp-host-groups = {
  master = [
    ${join(",", formatlist("\"%v\"", aws_network_interface.mastervip.*.private_ip))}
  ]

  proxy = [
    ${var.proxy["nodes"] > 0 ?
      join(",", formatlist("\"%v\"", aws_network_interface.proxyvip.*.private_ip)) :
      join(",", formatlist("\"%v\"", aws_network_interface.mastervip.*.private_ip))
    }
  ]
  worker = [
    ${join(",", formatlist("\"%v\"", aws_instance.icpnodes.*.private_ip))}
  ]

  // make the master nodes managements nodes if we don't have any specified
  management = [
    ${var.management["nodes"] > 0 ?
      join(",", formatlist("\"%v\"", aws_instance.icpmanagement.*.private_ip)) :
      join(",", formatlist("\"%v\"", aws_network_interface.mastervip.*.private_ip))
    }
  ]

  va = [
    ${join(",", formatlist("\"%v\"", aws_instance.icpva.*.private_ip))}
  ]
}

# Provide desired ICP version to provision
icp-inception = "${local.icp-version}"

/* Workaround for terraform issue #10857
  When this is fixed, we can work this out automatically */
cluster_size  = "${1 + var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"] + var.management["nodes"] + var.va["nodes"]}"

###################################################################################################################################
## You can feed in arbitrary configuration items in the icp_configuration map.
## Available configuration items availble from https://www.ibm.com/support/knowledgecenter/SSBS6K_3.1.0/installing/config_yaml.html
icp_configuration = {
  network_cidr                    = "${var.icp_network_cidr}"
  service_cluster_ip_range        = "${var.icp_service_network_cidr}"
  proxy_lb_address                = "${aws_lb.icp-proxy.dns_name}"
  cluster_lb_address              = "${aws_lb.icp-console.dns_name}"
  cluster_CA_domain               = "${var.user_provided_cert_dns != "" ? var.user_provided_cert_dns : aws_lb.icp-console.dns_name}"
  cluster_name                    = "${var.instance_name}-${random_id.clusterid.hex}-cluster"
  calico_ip_autodetection_method  = "interface=eth0"
  kubelet_nodename                = "fqdn"
${var.use_aws_cloudprovider ? "
  cloud_provider                  = \"aws\"" : "" }
  calico_tunnel_mtu               = "8981"

  # An admin password will be generated if not supplied in terraform.tfvars
  default_admin_password          = "${local.icppassword}"

  # This is the list of disabled management services
  #management_services             = ${jsonencode(local.disabled_management_services)}

  private_registry_enabled        = "${var.registry_server != "" ? "true" : "false" }"
  private_registry_server         = "${local.registry_server}"
  image_repo                      = "${local.image_repo}" # Will either be our private repo or external repo
  docker_username                 = "${local.docker_username}" # Will either be username generated by us or supplied by user
  docker_password                 = "${local.docker_password}" # Will either be username generated by us or supplied by user
}

# because not everything fits into the above map which is string-only key-value paris, provide a separate
# config file with complex types to be merged
icp_config_file = "./icp-terraform-config.yaml"

# We will let terraform generate a new ssh keypair
# for boot master to communicate with worker and proxy nodes
# during ICP deployment
generate_key = true

# SSH user and key for terraform to connect to newly created VMs
# ssh_key is the private key corresponding to the public assumed to be included in the template
ssh_user        = "icpdeploy"
ssh_key_base64  = "${base64encode(tls_private_key.installkey.private_key_pem)}"
ssh_agent       = false

EOF
}


resource "tls_private_key" "installkey" {
  algorithm   = "RSA"
}

# kick off the installer from the bastion node, if one exists.  otherwise it will get kicked off from cloud-init
resource "null_resource" "start_install" {
  # trigger a reinstall if the cluster config changes
  triggers {
    terraform_tfvars_contents = "${aws_s3_bucket_object.terraform_tfvars.content}"
    icp_config_yaml_contents = "${aws_s3_bucket_object.icp_config_yaml.content}"
  }

  count = "${var.bastion["nodes"] != 0 ? 1 : 0}"
  
  provisioner "remote-exec" {
    connection {
      host          = "${aws_instance.icpmaster.0.private_ip}"
      user          = "icpdeploy"
      private_key   = "${tls_private_key.installkey.private_key_pem}"
      bastion_host  = "${aws_instance.bastion.0.public_ip}"
    }

    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "sudo /tmp/icp_scripts/start_install.sh -i ${local.icp-version} -b ${aws_s3_bucket.icp_config_backup.id} ${local.image_package_uri != "" ? "-c ${local.image_package_uri}" : "" }"
    ]
  }
}

output "ICP Console ELB DNS (internal)" {
  value = "${aws_lb.icp-console.dns_name}"
}

output "ICP Proxy ELB DNS (internal)" {
  value = "${aws_lb.icp-proxy.dns_name}"
}

output "ICP Console URL" {
  value = "https://${var.user_provided_cert_dns != "" ? var.user_provided_cert_dns : aws_lb.icp-console.dns_name}:8443"
}

output "ICP Registry ELB URL" {
  value = "https://${aws_lb.icp-console.dns_name}:8500"
}

output "ICP Kubernetes API URL" {
  value = "https://${aws_lb.icp-console.dns_name}:8001"
}

output "ICP Admin Username" {
  value = "admin"
}

output "ICP Admin Password" {
  value = "${local.icppassword}"
}
