data "terraform_remote_state" "nomad" {
  backend = "local"

  config {
    path = "${path.module}/../../nomad/terraform-aws/terraform.tfstate"
  }
}

module "images-aws" {
  //source        = "git@github.com:hashicorp-modules/images-aws.git?ref=2017-07-03"
  source = "../../../modules/images-aws"
  nomad_version = "${var.nomad_version}"
  os            = "${var.os}"
  os_version    = "${var.os_version}"
}

data "template_file" "user_data_control" {
  template = "${file("${path.module}/init.tpl")}"
  vars = {
    cluster_size     = "${var.cluster_size}"
    consul_as_server = "${var.consul_as_server}"
    environment_name = "${data.terraform_remote_state.nomad.random_id_environment_hex}"
    nomad_as_client  = "${var.nomad_as_client}"
    nomad_as_server  = "${var.nomad_as_server}"
    nomad_use_consul = "true"
  }
}

resource "aws_instance" "control" {
  ami                    = "${module.images-aws.nomad_image}"
  instance_type          = "${var.instance_type}"
  key_name               = "${data.terraform_remote_state.nomad.ssh_key_name}"
  vpc_security_group_ids = ["${data.terraform_remote_state.nomad.nomad_server_sg_id}"]
  subnet_id              ="${data.terraform_remote_state.nomad.subnet_public_ids.0}"
  count                  = "1"
  user_data              = "${data.template_file.user_data_control.rendered}"
 // iam_instance_profile  = "${aws_iam_instance_profile.nomad_controller.id}"
  iam_instance_profile  = "${data.terraform_remote_state.nomad.iam_instance_profile_nomad_server}"
  #Instance tags
  tags {
    Name                = "${format("%s Nomad Control Server",data.terraform_remote_state.nomad.random_id_environment_hex)}"
    Cluster-Name        = "${data.terraform_remote_state.nomad.random_id_environment_hex}-Nomad-Control-Node"
    Environment-Nam     = "${data.terraform_remote_state.nomad.random_id_environment_hex}"
    propagate_at_launch = true
  }
}

/*
resource "aws_security_group" "control_sg" {
  name        = "nomad-control-server-sg"
  description = "Security Group for Nomad Control Server"
  tags {
    Name         = "Nomad Control Server SG"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["${module.network-aws.vpc_cidr_block}"]
  }  
  # TCP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # UDP All outbound traffic
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Used for HDFS communication
  ingress {
    from_port   = 8020
    to_port     = 8020
    protocol    = "tcp"
    cidr_blocks = ["${module.network-aws.vpc_cidr_block}"]
  }
}
*/




