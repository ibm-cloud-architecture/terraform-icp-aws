provider "aws" {
  region = "${var.aws_region}"
}

data "aws_caller_identity" "current" {
}

resource "null_resource" "install_aws_cli" {
  provisioner "local-exec" {
    command = <<EOF
if [ -e "${path.module}/awscli/bin/aws" ]; then
  echo "AWS CLI already installed!"
  exit 0
fi

awscli=`which aws`
if [ ! -z $awscli ]; then
  mkdir -p ${path.module}/awscli/bin
  ln -s $awscli ${path.module}/awscli/bin
  echo "AWS CLI already installed!"
  exit 0;
fi

curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip awscli-bundle.zip
./awscli-bundle/install -i ${path.module}/awscli -b ${path.module}/awscli/bin/aws

EOF
  }
}
