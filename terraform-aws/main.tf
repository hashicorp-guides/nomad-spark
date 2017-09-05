data "terraform_remote_state" "nomad" {
  backend = "local"

  config {
    path = "${path.module}/../../nomad/aws.tfstate"
  }
}

data "aws_ami" "control" {
  most_recent = true
  owners = ["self"]
  filter {
    name = "name"
    values = ["production-nomad-server-0.6.0*-RHEL*"]
  }
}

module "ssh-keypair-aws" {
  source       = "github.com/hashicorp-modules/ssh-keypair-aws?ref=0.1.0"
  ssh_key_name = "nomad_control_key"
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
  ami                    = "${data.aws_ami.control.id}"
  instance_type          = "${var.instance_type}"
  key_name               = "${module.ssh-keypair-aws.ssh_key_name}"
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
