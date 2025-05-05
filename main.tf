provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# --- Find Latest Ubuntu 22.04 LTS AMI --- #
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID
  provider    = aws # Explicit provider for data source if needed

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] # Ubuntu 22.04 LTS
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# --- Networking --- #
resource "aws_vpc" "rustdesk_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.server_name_tag}-VPC"
  }
}

resource "aws_internet_gateway" "rustdesk_gw" {
  vpc_id = aws_vpc.rustdesk_vpc.id
  tags = {
    Name = "${var.server_name_tag}-IGW"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "rustdesk_public_subnet" {
  vpc_id                  = aws_vpc.rustdesk_vpc.id
  cidr_block              = var.subnet_cidr
  # Use specified AZ or the first available one if null
  availability_zone       = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.server_name_tag}-PublicSubnet"
  }
}

resource "aws_route_table" "rustdesk_public_rt" {
  vpc_id = aws_vpc.rustdesk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rustdesk_gw.id
  }

  tags = {
    Name = "${var.server_name_tag}-PublicRouteTable"
  }
}

resource "aws_route_table_association" "rustdesk_public_assoc" {
  subnet_id      = aws_subnet.rustdesk_public_subnet.id
  route_table_id = aws_route_table.rustdesk_public_rt.id
}

# --- Security Group --- #
resource "aws_security_group" "rustdesk_sg" {
  name        = "${lower(var.server_name_tag)}-sg"
  description = "Allow RustDesk OSS/Pro and SSH Ports"
  vpc_id      = aws_vpc.rustdesk_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr
  }

  ingress {
    description = "RustDesk TCP Ports"
    from_port   = 21115
    to_port     = 21119 # Covers hbbs/hbbr/api/pro ports
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RustDesk Relay (UDP)"
    from_port   = 21116
    to_port     = 21116
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.server_name_tag}-SG"
  }
}

# --- IAM Role and Policy for Secrets Manager Access (Conditional) --- #
locals {
  # Determine if we need IAM resources for Secrets Manager
  deploy_pro_with_secret = var.deploy_pro_version && var.rustdesk_pro_license_secret_name != ""
  
  # Construct secret ARN only if needed
  secret_arn = local.deploy_pro_with_secret ? "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.rustdesk_pro_license_secret_name}" : null
  
  # Condition for creating IAM resources (renamed for clarity)
  create_iam_for_secrets = local.deploy_pro_with_secret
}

resource "aws_iam_role" "rustdesk_instance_role" {
  count = local.create_iam_for_secrets ? 1 : 0
  name  = "${var.server_name_tag}-InstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name = "${var.server_name_tag}-InstanceRole"
  }
}

resource "aws_iam_policy" "rustdesk_secrets_policy" {
  count = local.create_iam_for_secrets ? 1 : 0
  name  = "${var.server_name_tag}-SecretsPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Effect   = "Allow",
        Resource = [local.secret_arn] # Reference the constructed ARN
      }
    ]
  })
  tags = {
    Name = "${var.server_name_tag}-SecretsPolicy"
  }
}

resource "aws_iam_role_policy_attachment" "rustdesk_secrets_attach" {
  count      = local.create_iam_for_secrets ? 1 : 0
  role       = aws_iam_role.rustdesk_instance_role[0].name
  policy_arn = aws_iam_policy.rustdesk_secrets_policy[0].arn
}

resource "aws_iam_instance_profile" "rustdesk_instance_profile" {
  count = local.create_iam_for_secrets ? 1 : 0
  name  = "${var.server_name_tag}-InstanceProfile"
  role  = aws_iam_role.rustdesk_instance_role[0].name
  tags = {
    Name = "${var.server_name_tag}-InstanceProfile"
  }
}

# --- EC2 Instance --- #
resource "aws_instance" "rustdesk_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.rustdesk_public_subnet.id
  vpc_security_group_ids = [aws_security_group.rustdesk_sg.id]
  # Assign IAM profile only if it was created
  iam_instance_profile   = local.create_iam_for_secrets ? aws_iam_instance_profile.rustdesk_instance_profile[0].name : null

  user_data_replace_on_change = true # Rerun script if it changes
  user_data = templatefile("${path.module}/install_rustdesk.sh.tftpl", {
    # Pass variables to the template
    deploy_pro_version = var.deploy_pro_version
    secret_name        = var.rustdesk_pro_license_secret_name
    aws_region         = var.aws_region
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = var.server_name_tag
  }

  # Ensure network resources are created before the instance
  depends_on = [
    aws_internet_gateway.rustdesk_gw,
    aws_route_table_association.rustdesk_public_assoc,
  ]
} 