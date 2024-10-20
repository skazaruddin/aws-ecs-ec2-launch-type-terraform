terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = " 5.72.1"  # Adjust version as per your requirement
    }
  }

  required_version = ">= 1.0.0"
}
provider "aws" {
  region = "ap-south-1"  # Adjust region as per your setup
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_subnet" {
  count = 2
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = cidrsubnet(aws_vpc.my_vpc.cidr_block, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  count = 2
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = cidrsubnet(aws_vpc.my_vpc.cidr_block, 8, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  count = 2
  subnet_id = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}


# Create route table for private subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id
}




# Allocate an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# Create NAT Gateway in the public subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
      subnet_id     = aws_subnet.public_subnet[0].id # Assume NAT gateway goes into the first public subnet
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "gw NAT"
  }
}

# Add route in the private route table for NAT Gateway
resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}
