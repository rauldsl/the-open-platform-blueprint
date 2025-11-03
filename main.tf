terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "k8s" {
  cidr_block = "10.10.0.0/16"
  tags = { Name = "k8s-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.k8s.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "k8s-subnet-1" }
}

data "aws_availability_zones" "available" {}

resource "aws_security_group" "k8s_nodes" {
  name   = "k8s-nodes-sg"
  vpc_id = aws_vpc.k8s.id

  ingress {
    description = "all k8s traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.10.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr] # your IP
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
}

locals {
  control_count = 3
}

resource "aws_instance" "control" {
  count         = local.control_count
  ami           = var.ami_id
  instance_type = var.control_instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = aws_key_pair.admin.key_name
  security_groups = [aws_security_group.k8s_nodes.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/cloudinit/control-userdata.tpl", {
    is_first = count.index == 0 ? "true" : "false"
    kube_version = var.kube_version
  })
  tags = { Name = "k8s-control-${count.index}" }
  provisioner "remote-exec" {
    inline = [
      "echo 'node ready'"
    ]
    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = self.public_ip
    }
  }
}

resource "aws_launch_template" "worker_lt" {
  name_prefix   = "k8s-worker-"
  image_id      = var.ami_id
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.admin.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.k8s_nodes.id]
  }

  user_data = base64encode(templatefile("${path.module}/cloudinit/worker-userdata.tpl", {
    kube_version = var.kube_version
  }))
}

resource "aws_autoscaling_group" "workers" {
  desired_capacity     = var.worker_desired_count
  max_size             = var.worker_max_count
  min_size             = var.worker_min_count
  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.public.id]
  tags = [{
    key                 = "Name"
    value               = "k8s-worker"
    propagate_at_launch = true
  }]
}
