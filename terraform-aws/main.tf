resource "random_id" "environment_name" {
  byte_length = 4
  prefix      = "${var.environment_name_prefix}-"
}

module "images-aws" {
  source        = "git@github.com:hashicorp-modules/images-aws.git?ref=2017-07-03"
  nomad_version = "${var.nomad_version}"
  os            = "${var.os}"
  os_version    = "${var.os_version}"
}

module "network-aws" {
  //source           = "git@github.com:hashicorp-modules/network-aws.git?ref=2017-05-31"
  source           = "../../../modules/network-aws"
  environment_name = "${random_id.environment_name.hex}"
  os               = "${var.os}"
  os_version       = "${var.os_version}"
  ssh_key_name     = "${module.ssh-keypair-aws.ssh_key_name}"
}

module "ssh-keypair-aws" {
  source       = "git@github.com:hashicorp-modules/ssh-keypair-aws.git"
  ssh_key_name = "${random_id.environment_name.hex}"
}

module "consul-aws" {
  source           = "git@github.com:hashicorp-modules/consul-aws.git?ref=2017-06-02"
  cluster_name     = "${random_id.environment_name.hex}-consul-asg"
  cluster_size     = "${var.cluster_size}"
  consul_version   = "${var.consul_version}"
  environment_name = "${random_id.environment_name.hex}"
  instance_type    = "${var.instance_type}"
  os               = "${var.os}"
  os_version       = "${var.os_version}"
  ssh_key_name     = "${module.ssh-keypair-aws.ssh_key_name}"
  subnet_ids       = "${module.network-aws.subnet_public_ids}"
  vpc_id           = "${module.network-aws.vpc_id}"
}

module "nomad-aws-server" {
  //source              = "git@github.com:hashicorp-modules/nomad-aws.git?ref=2017-06-02"
  source              = "../../../modules/nomad-aws"
  cluster_name        = "${random_id.environment_name.hex}-nomad-SERVER-asg"
  cluster_size        = "${var.cluster_size}"
  consul_server_sg_id = "${module.consul-aws.consul_server_sg_id}"
  consul_as_server    = "${var.consul_as_server}"
  environment_name    = "${random_id.environment_name.hex}"
  nomad_as_client     = "${var.nomad_as_client}"
  nomad_as_server     = "${var.nomad_as_server}"
  nomad_version       = "${var.nomad_version}"
  instance_type       = "${var.instance_type}"
  os                  = "${var.os}"
  os_version          = "${var.os_version}"
  ssh_key_name        = "${module.ssh-keypair-aws.ssh_key_name}"
  subnet_ids          = "${module.network-aws.subnet_public_ids}"
  vpc_id              = "${module.network-aws.vpc_id}"
  vpc_cidr_block      = "${module.network-aws.vpc_cidr_block}"

  custom_user_init  = "${var.custom_user_init}"

}

module "nomad-aws-client" {
  //source              = "git@github.com:hashicorp-modules/nomad-aws.git?ref=2017-06-02"
  source              = "../../../modules/nomad-aws"
  cluster_name        = "${random_id.environment_name.hex}-nomad-CLIENT-asg"
  cluster_size        = "${var.cluster_size}"
  consul_server_sg_id = "${module.consul-aws.consul_server_sg_id}"
  consul_as_server    = "${var.consul_as_server}"
  environment_name    = "${random_id.environment_name.hex}"
  nomad_as_client     = "${var.nomad_as_client_group2}"
  nomad_as_server     = "${var.nomad_as_server_group2}"
  nomad_version       = "${var.nomad_version}"
  instance_type       = "${var.instance_type}"
  os                  = "${var.os}"
  os_version          = "${var.os_version}"
  ssh_key_name        = "${module.ssh-keypair-aws.ssh_key_name}"
  subnet_ids          = "${module.network-aws.subnet_public_ids}"
  vpc_id              = "${module.network-aws.vpc_id}"
  vpc_cidr_block      = "${module.network-aws.vpc_cidr_block}"
}

data "template_file" "user_data_control" {
  template = "${file("${path.module}/init.tpl")}"
  vars = {
    cluster_size     = "${var.cluster_size}"
    consul_as_server = "${var.consul_as_server}"
    environment_name = "${random_id.environment_name.hex}"
    nomad_as_client  = "${var.nomad_as_client}"
    nomad_as_server  = "${var.nomad_as_server}"
    nomad_use_consul = "true"
  }
}

resource "aws_instance" "control" {
  ami                    = "${module.images-aws.nomad_image}"
  instance_type          = "${var.instance_type}"
  key_name               = "${module.ssh-keypair-aws.ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.control_sg.id}"]
  subnet_id              = "${module.network-aws.subnet_public_ids[0]}"
  count                  = "1"
  user_data              = "${data.template_file.user_data_control.rendered}"

  #Instance tags
  tags {
    Name                = "${format("%s Nomad Control Server",random_id.environment_name.hex)}"
    Cluster-Name        = "${random_id.environment_name.hex}-Nomad-Control-Node"
    Environment-Nam     = "${random_id.environment_name.hex}"
    propagate_at_launch = true
  }

  //iam_instance_profile = "${aws_iam_instance_profile.instance_profile.name}"
  iam_instance_profile = "${module.nomad-aws-server.instance_profile}"
}

resource "aws_security_group" "control_sg" {
  name        = "nomad-control-server-sg"
  description = "Security Group for Nomad Control Server"
  vpc_id      = "${module.network-aws.vpc_id}"
  tags {
    Name         = "Nomad Control Server"
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

  ingress {
    from_port   = 8020
    to_port     = 8020
    protocol    = "tcp"
    cidr_blocks = ["${module.network-aws.vpc_cidr_block}"]
  }
}




