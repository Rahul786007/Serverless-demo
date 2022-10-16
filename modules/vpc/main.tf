variable "prefix" {}
variable "vpc_cidr_block" {}
variable "pubic_subnets" {}
variable "private_subnets" {}
variable "private_subnets_blocks" {  }
variable "public_subnets_blocks" {}
variable "region" { }
variable "vpc_endpoint_endpoints_sg" { }
data "aws_availability_zones" "available" {
   state = "available"
}
resource "aws_vpc" "vpc" {
   cidr_block           = var.vpc_cidr_block
   enable_dns_hostnames = true
   enable_dns_support   = true

   tags = {
      Name = "${var.prefix}-vpc"
   }
}
resource "aws_internet_gateway" "igw" {
   vpc_id = aws_vpc.vpc.id

   tags = {
      Name = "${var.prefix}-igw"
   }
}
resource "aws_subnet" "public_subnet" {
   count             = var.public_subnets
   vpc_id            = aws_vpc.vpc.id
   cidr_block        = var.public_subnet_blocks[count.index]
   availability_zone = data.aws_availability_zones.available.names[count.index]

   # Tags will be formatted like: PREFIX-public-subnet-01, PREFIX-public-subnet-02
   tags = {
      Name = "${format("${var.prefix}-public-subnet-%02d", count.index + 1)}"
   }
}

resource "aws_subnet" "private_subnet" {
   count             = var.private_subnets
   vpc_id            = aws_vpc.vpc.id
   cidr_block        = var.private_subnet_blocks[count.index]
   availability_zone = data.aws_availability_zones.available.names[count.index]

   # Tags will be formatted like: PREFIX-public-subnet-01, PREFIX-private-subnet-02
   tags = {
      Name = "${format("${var.prefix}-private_subnet-%02d", count.index + 1)}"
   }
}
resource "aws_route_table" "public_rt" {
   vpc_id = aws_vpc.vpc.id

   route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
   }

   tags = {
      Name = "${var.prefix}-public-rt"
   }
}
resource "aws_route_table_association" "public" {
   count          = var.public_subnets
   route_table_id = aws_route_table.public_rt.id
   subnet_id      = aws_subnet.public_subnet[count.index].id
}
resource "aws_eip" "nat_gateway_eip" {
   vpc = true   

   tags = {
      Name = "${var.prefix}-eip"
   }
}
resource "aws_nat_gateway" "at_gateway_eip" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.private_subnet.id

  tags = {
    Name = "gw NAT"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.example]
}

resource "aws_eip" "nat_gateway_eip" {
   vpc = true   

   tags = {
      Name = "${var.prefix}-eip"
   }
}
aws_subnet.private_subnet[0].id


resource "aws_route_table" "private_rt" {
   vpc_id = aws_vpc.vpc.id

   route {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat_gateway.id
   }

   tags = {
      Name = "${var.prefix}-private-rt"
   }
}

resource "aws_route_table_association" "private" {
   count          = var.private_subnets
   route_table_id = aws_route_table.private_rt.id
   subnet_id      = aws_subnet.private_subnet[count.index].id
}

resource "aws_vpc_endpoint" "s3" {
   vpc_id            = aws_vpc.vpc.id
   service_name      = "com.amazonaws.${var.region}.s3"
   vpc_endpoint_type = "Gateway"

   tags = {
      Name = "${var.prefix}-s3-endpoint"
   }
}


resource "aws_vpc_endpoint_route_table_association" "s3_endpoint" {
   route_table_id    = aws_route_table.private_rt.id
   vpc_endpoint_id   = aws_vpc_endpoint.s3.id
}

locals {
   endpoints = [
      "com.amazonaws.${var.region}.sts",
      "com.amazonaws.${var.region}.ecr.api",
      "com.amazonaws.${var.region}.ecr.dkr",
      "com.amazonaws.${var.region}.logs",
      "com.amazonaws.${var.region}.ecs"
   ]
}
resource "aws_vpc_endpoint" "endpoint" {
   count          = length(local.endpoints)
   vpc_id         = aws_vpc.vpc.id
   service_name   = local.endpoints[count.index]

   subnet_ids           = [for subnet in aws_subnet.private_subnet : subnet.id]
   security_group_ids   = [var.vpc_endpoints_sg]
   private_dns_enabled  = true
   vpc_endpoint_type    = "Interface"

   tags = {
      Name = "${var.prefix}-${
         try(
            replace(split(local.endpoints[count.index], "${var.region}.")[1]), ".", "-",
            split(local.endpoints[count.index], ".")[3]
         )
      }-endpoint"
   }
}