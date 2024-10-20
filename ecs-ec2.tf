data "aws_ami" "amzn2_ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}


resource "aws_security_group" "ec2_sg" {
  name        = "ecs-instance-sg"
  description = "Security group for ECS instances"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "MyEcsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}

resource "aws_iam_role" "ecs_task_execution_role" {

  name = "MyEcsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "quran_logs" {
  name              = "/ecs/quran-logs"
  retention_in_days = 30
}


resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecs_cluster" "my_ecs_cluster" {
  name = "my-ecs-cluster"
  setting {
      name  = "containerInsights"
      value = "enabled"
  }
#   Execute Command Configuration with Override Logging

#   configuration {
#       execute_command_configuration {
#         kms_key_id = aws_kms_key.example.arn
#         logging    = "OVERRIDE"
#
#         log_configuration {
#           cloud_watch_encryption_enabled = true
#           cloud_watch_log_group_name     = aws_cloudwatch_log_group.example.name
#         }
#       }
#     }
}

resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-launch-template"
  image_id      = data.aws_ami.amzn2_ecs_optimized.id
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

user_data = base64encode(<<-EOF
    #!/bin/bash
    cat << 'EOL' >> /etc/ecs/ecs.config
    ECS_CLUSTER=${aws_ecs_cluster.my_ecs_cluster.name}
    ECS_LOGLEVEL=info
    EOL
  EOF
  )
}

resource "aws_autoscaling_group" "ecs_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.private_subnet[*].id

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }
   health_check_type         = "ELB"
   health_check_grace_period = 300

   instance_maintenance_policy {
       min_healthy_percentage = 100
       max_healthy_percentage = 200
     }

   tag {
      key                 = "Name"
      value               = "ecs-instance"
      propagate_at_launch = true
   }

    # Ensure to use VPC settings instead of EC2-Classic or default VPC settings
   force_delete         = true



}

resource "aws_ecs_capacity_provider" "my_capacity_provider" {
  name = "my-capacity-provider"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      status = "ENABLED"
    }
    managed_termination_protection = "DISABLED"
  }
}

variable "enabled_default_capacity_provider" {
  type    = bool
  default = true
}
resource "aws_ecs_cluster_capacity_providers" "capacity_providers" {
  cluster_name         = aws_ecs_cluster.my_ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.my_capacity_provider.name]  # Use .name here

   dynamic "default_capacity_provider_strategy" {
      for_each = var.enabled_default_capacity_provider ? [1] : []
      content {
        base              = 1
        weight            = 100
        capacity_provider = aws_ecs_capacity_provider.my_capacity_provider.name
      }
    }
}
