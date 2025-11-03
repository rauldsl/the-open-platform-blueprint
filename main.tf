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
