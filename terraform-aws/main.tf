data "terraform_remote_state" "nomad" {
  backend = "local"

  config {
    path = "${path.module}/../../nomad/aws.tfstate"
  }
}

module "images-aws" {
  source        = "git@github.com:hashicorp-modules/images-aws.gitref=2017-08-10"
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
  subnet_id              = "${data.terraform_remote_state.nomad.subnet_public_ids.0}"
  count                  = "1"
  user_data              = "${data.template_file.user_data_control.rendered}"
  iam_instance_profile   = "${data.terraform_remote_state.nomad.iam_instance_profile_nomad_server}"

  #Instance tags
  tags {
    Name                = "${format("%s Nomad Control Server",data.terraform_remote_state.nomad.random_id_environment_hex)}"
    Cluster-Name        = "${data.terraform_remote_state.nomad.random_id_environment_hex}-Nomad-Control-Node"
    Environment-Nam     = "${data.terraform_remote_state.nomad.random_id_environment_hex}"
    propagate_at_launch = true
  }
}
