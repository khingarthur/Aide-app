# vpc, subnet, route tables, gateways, eip, sg, target group,
# lauch template, load balancer

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "app" {
  cidr_block = var.cidre_1

  tags = {
    Name = "Flask-App"
  }
}

# cidre block for vpc
variable "cidre_1" {
  type = string
  default = "10.0.1.0/16"
}

# cidre block to allow all ips
variable "cidre_2" {
  type = string
  default = "0.0.0.0/0"
}

# Variables for multiple resources
variable "multiple" {
  type    = number
  default = 2
}

# Availability zones
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

resource "aws_subnet" "private_sn" {
  count = var.multiple

  vpc_id                  = aws_vpc.app.id
  cidr_block              = cidrsubnet("${var.cidre_1}", 4, count.index) # Adjust based on CIDR split
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "public_sn" {
  count = var.multiple

  vpc_id                  = aws_vpc.app.id
  cidr_block              = cidrsubnet("${var.cidre_1}", 4, count.index) # Adjust based on CIDR split
  availability_zone       = var.azs[count.index]

  tags = {
    Name = "Public-Subnet ${count.index + 1}"
  }
}

resource "aws_route_table" "public_rt" {
  count = var.multiple
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = var.cidre_2
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { 
    Name = "Publice-rt ${count.indx + 1}"
  }
}

resource "aws_route_table_association" "public_association" {
  count = var.multiple

  subnet_id      = aws_subnet.public_rt[count.index].id
  route_table_id = aws_route_table.public_rt[count.index].id
}

resource "aws_route_table" "private_rt" {
  count = var.multiple

  vpc_id = aws_vpc.app.id

  route {
    cidr_block = var.cidre_2
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }
}

resource "aws_route_table_association" "private_association" {
  count = var.multiple

  subnet_id      = aws_subnet.private_sn[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id

}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "flask-igw"
  }
}

resource "aws_eip" "eip" {
  count = var.multiple

  # The allocation of an EIP for each NAT Gateway
}

resource "aws_nat_gateway" "nat_gateway" {
  count = var.multiple

  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = aws_subnet.public_sn[count.index].id

  tags = {
    Name = "NAT-Gateway ${count.index + 1}"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
 
   depends_on = [aws_internet_gateway.example]
}


resource "aws_lb" "app" {
  name               = "aide-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id] 
  subnets            = [aws_subnet.public_sn[0].id, aws_subnet.public_sn[1].id]

  enable_deletion_protection = true

  tags = {
    Environment = "Dev"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "aide-app-lb-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.app.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Security Group for Load Balancer
resource "aws_security_group" "lb_sg" {
  vpc_id = aws_vpc.app.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.cidre_2}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.cidre_2}"]
  }

  tags = {
    Name = "lb-sg"
  }
}

# Security Group for App Instances
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.app.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.cidre_2}"]
  }

  tags = {
    Name = "app-sg"
  }
}

# Launch Template

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-lunar-23.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-launch-template-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  key_name = "Linux_Machine" # Replace with your key pair name

  user_data = filebase64("${path.module}/script.sh")

  vpc_security_group_ids = [aws_security_group.app_sg.id]


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Flask-App"
    }
  }
}


# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = [ aws_subnet.private_sn[count.index].id ]

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  min_size           = 1
  max_size           = 3
  desired_capacity   = 1

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }
}

# Scaling Policy


# Target Tracking Scaling Policy for Load Balancer Request Count
resource "aws_autoscaling_policy" "request_count_policy" {
  name                   = "request-count-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app_tg.arn_suffix}"
    }

    target_value         = 50  # Target 50 requests per target
    /*
    estimated_instance_warmup = 120 
    scale_in_cooldown    = 120 # 5 minutes cooldown period for scale in
    scale_out_cooldown   = 120 # 5 minutes cooldown period for scale out
    */

   }
}

# https://github.com/ooghenekaro/argocd-amazon-manifest

# https://github.com/ooghenekaro/Amazon-clone-Dockerized