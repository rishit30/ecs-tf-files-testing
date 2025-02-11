# Blueprint for ECS Cluster with Application Load Balancer

# AWS Provider Configuration
# REQUIRED: Set your preferred AWS region
provider "aws" {
  region = "us-east-1"  # [Customizable] Change to your preferred region
}

# VPC Configuration
# Creates a Virtual Private Cloud with DNS support
resource "aws_vpc" "testing-app_vpc" {
  cidr_block           = "10.0.0.0/16"  # [Customizable] VPC CIDR range
  enable_dns_hostnames = true           
  enable_dns_support   = true           

  tags = {
    Name = "testing-app-vpc"  # [Customizable] VPC name
  }
}

# Internet Gateway
# Enables internet access for the VPC
resource "aws_internet_gateway" "testing-app_igw" {
  vpc_id = aws_vpc.testing-app_vpc.id

  tags = {
    Name = "testing-app-igw"  # OPTIONAL: internet gateway name tag
  }
}

# Public Subnets
# REQUIRED: At least two subnets in different AZs for high availability
resource "aws_subnet" "testing-app_public_1" {
  vpc_id                  = aws_vpc.testing-app_vpc.id
  cidr_block              = "10.0.1.0/24"  # [Customizable] Subnet CIDR range
  availability_zone       = "us-east-1a"    # [Customizable] AZ selection
  map_public_ip_on_launch = true           

  tags = {
    Name = "testing-app-public-1"  # [Customizable] Subnet name
  }
}

resource "aws_subnet" "testing-app_public_2" {
  vpc_id                  = aws_vpc.testing-app_vpc.id
  cidr_block              = "10.0.2.0/24"  # [Customizable] Subnet CIDR range
  availability_zone       = "us-east-1b"    # [Customizable] AZ selection
  map_public_ip_on_launch = true           

  tags = {
    Name = "testing-app-public-2"  # [Customizable] Subnet name
  }
}

# Route Table
# Manages routing for the public subnets
resource "aws_route_table" "testing-app_public_rt" {
  vpc_id = aws_vpc.testing-app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.testing-app_igw.id
  }

  tags = {
    Name = "testing-app-public-rt"  # OPTIONAL: Route table name tag
  }
}

# Route Table Associations
# Links the public subnets with the route table
resource "aws_route_table_association" "testing-app_public_1" {
  subnet_id      = aws_subnet.testing-app_public_1.id
  route_table_id = aws_route_table.testing-app_public_rt.id
}

resource "aws_route_table_association" "testing-app_public_2" {
  subnet_id      = aws_subnet.testing-app_public_2.id
  route_table_id = aws_route_table.testing-app_public_rt.id
}

# Security Group for ALB
# Defines inbound and outbound traffic rules for the load balancer
resource "aws_security_group" "testing-app_alb_sg" {
  name        = "testing-app-alb-sg"  # [Customizable] Security group name
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.testing-app_vpc.id

  # HTTP Access
  ingress {
    from_port   = 80  # [Customizable] Ingress port
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # [Customizable] IP range restriction
  }

  # Outbound Traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "testing-app-alb-sg"  # OPTIONAL: Security group name tag
  }
}

# Security Group for ECS Tasks
# Defines inbound and outbound traffic rules for the containers
resource "aws_security_group" "testing-app_ecs_sg" {
  name        = "testing-app-ecs-sg"  # [Customizable] Security group name
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.testing-app_vpc.id

  # Application Port Access
  ingress {
    from_port       = 8080           # [Customizable] Application port
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.testing-app_alb_sg.id]
  }

  # Outbound Traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "testing-app-ecs-sg"  # OPTIONAL: Security group name tag
  }
}

# Application Load Balancer
# Distributes traffic across ECS tasks
resource "aws_lb" "testing-app_alb" {
  name               = "testing-app-alb"  # [Customizable] ALB name
  internal           = false              # [Customizable] Internal/External ALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.testing-app_alb_sg.id]
  subnets           = [aws_subnet.testing-app_public_1.id, aws_subnet.testing-app_public_2.id]

  tags = {
    Name = "testing-app-alb"  # OPTIONAL: ALB name tag
  }
}

# Target Group
# Defines health check and routing rules for the ALB
resource "aws_lb_target_group" "testing-app_tg" {
  name        = "testing-app-tg"  # [Customizable] Target group name
  port        = 8080             # [Customizable] Application port
  protocol    = "HTTP"           # [Customizable] Protocol (HTTP/HTTPS)
  vpc_id      = aws_vpc.testing-app_vpc.id
  target_type = "ip"            # REQUIRED: Use IP targets for Fargate

  # Health Check Configuration
  health_check {
    enabled             = true
    path               = "/"      # [Customizable] Health check path
    interval            = 30      # [Customizable] Health check interval
    timeout            = 5        # [Customizable] Health check timeout
    healthy_threshold   = 2       
    unhealthy_threshold = 2
  }

  tags = {
    Name = "testing-app-tg"  # OPTIONAL: Target group name tag
  }
}

# ALB Listener
# Configures the ALB listening port and protocol
resource "aws_lb_listener" "testing-app_listener" {
  load_balancer_arn = aws_lb.testing-app_alb.arn
  port              = 80        # REQUIRED: External listening port
  protocol          = "HTTP"    # REQUIRED: Consider using HTTPS in production

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.testing-app_tg.arn
  }
}

# ECR Repository
# Stores Docker images for the application
resource "aws_ecr_repository" "testing-app_repo" {
  name = "testing-app"  # [Customizable] Repository name
}

# ECS Cluster
# Logical grouping of ECS tasks and services
resource "aws_ecs_cluster" "testing-app_cluster" {
  name = "testing-app-cluster"  # [Customizable] Cluster name
}

# ECS Task Definition
# Defines the container configuration
resource "aws_ecs_task_definition" "testing-app_task" {
  family                   = "testing-app-task"  # [Customizable] Task family name
  network_mode            = "awsvpc"           # REQUIRED: Required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                     = "256"              # [Customizable] CPU units
  memory                  = "512"              # [Customizable] Memory allocation
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  # Container Definition
  # REQUIRED: Update image URL with your application image
  container_definitions = jsonencode([
    {
      name  = "testing-app-container"  # [Customizable] Container name
      image = "${aws_ecr_repository.testing-app_repo.repository_url}:latest"  # [Customizable] Image tag
      portMappings = [
        {
          containerPort = 8080    # [Customizable] Container port
          hostPort      = 8080    # [Customizable] Host port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/testing-app"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group
# Stores container logs
resource "aws_cloudwatch_log_group" "testing-app_logs" {
  name              = "/ecs/testing-app"  # [Customizable] Log group name
  retention_in_days = 30                 # OPTIONAL: Log retention period
}

# IAM Role for ECS Task Execution
# Allows ECS to pull images and send logs
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "testing-app-ecs-execution-role"  # REQUIRED: Role name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Role Policies
# Attaches required permissions to the ECS execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_cloudwatch_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# ECS Service
# Manages the running tasks and integration with the ALB
resource "aws_ecs_service" "testing-app_service" {
  name            = "testing-app-service"  # [Customizable] Service name
  cluster         = aws_ecs_cluster.testing-app_cluster.id
  task_definition = aws_ecs_task_definition.testing-app_task.arn
  desired_count   = 1                     # [Customizable] Number of tasks
  launch_type     = "FARGATE"             # [Customizable] Launch type

  # Network Configuration
  network_configuration {
    subnets         = [aws_subnet.testing-app_public_1.id, aws_subnet.testing-app_public_2.id]
    security_groups = [aws_security_group.testing-app_ecs_sg.id]
    assign_public_ip = true  # [Customizable] Public IP assignment
  }

  # Load Balancer Integration
  load_balancer {
    target_group_arn = aws_lb_target_group.testing-app_tg.arn
    container_name   = "testing-app-container"
    container_port   = 8080  # REQUIRED: Match your application port
  }

  depends_on = [aws_lb_listener.testing-app_listener]
}

# Output Values
# Useful information about the created resources
output "ecr_repository_url" {
  value = aws_ecr_repository.testing-app_repo.repository_url
  description = "The URL of the ECR repository"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.testing-app_cluster.name
  description = "The name of the ECS cluster"
}

output "alb_dns_name" {
  value = aws_lb.testing-app_alb.dns_name
  description = "The DNS name of the load balancer"
}

output "execution_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
  description = "The ARN of the execution role"
}

output "service_name" {
  value = aws_ecs_service.testing-app_service.name
  description = "The name of the ECS service"
}   

output "cluster_name" {
  value = aws_ecs_cluster.testing-app_cluster.name
  description = "The name of the ECS cluster"
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.testing-app_task.arn
  description = "The ARN of the task definition"
}