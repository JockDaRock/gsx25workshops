# Configure the AWS provider
provider "aws" {
  region = "us-west-2"  # Change this to your desired region
}

# Data source to get the latest Deep Learning AMI
data "aws_ami" "deep_learning_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning AMI GPU *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = {
    Name = "ollama-vpc"
  }
}

# Create a subnet in us-west-2a
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"  # Explicitly set the AZ
  
  tags = {
    Name = "ollama-subnet"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ollama-igw"
  }
}

# Create a route table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "ollama-route-table"
  }
}

# Associate the route table with the subnet
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Create a security group
resource "aws_security_group" "ollama" {
  name        = "allow_ollama"
  description = "Allow Ollama inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ollama"
  }
}

# Create an EC2 instance
resource "aws_instance" "ollama" {
  ami               = "ami-060b8b561e3baba69" # data.aws_ami.deep_learning_ami.id
  instance_type     = "p3.16xlarge"
  availability_zone = "us-west-2a"  # Explicitly set the AZ
  
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.ollama.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 1000  # Increased size for GPU instance
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Run Ollama with GPU support
              docker run -d --gpus all -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
              EOF

  tags = {
    Name = "ollama-gpu-server"
  }
}

# Output the public IP of the EC2 instance
output "public_ip" {
  value = aws_instance.ollama.public_ip
}