
resource "aws_lb_target_group" "quran_target_group" {
  name        = "quran-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
  target_type = "ip"

  health_check {
    path = "/actuator/health"
  }
}


resource "aws_lb_listener" "quran_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8080  # Use the appropriate port for your service
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.quran_target_group.arn
  }
}

resource "aws_lb_listener_rule" "quran_service_rule" {
  listener_arn = aws_lb_listener.quran_listener.arn  # Use the existing listener ARN
  priority     = 0  # Priority for the rule; lower numbers are higher priority

  condition {
      path_pattern {
        values = ["/v1/surah*"]
      }
  }

#   condition {
#       host_header {
#         values = ["example.com"]
#       }
#     }

     action {
         type = "forward"
         target_group_arn = aws_lb_target_group.quran_target_group.arn
       }
}


resource "aws_ecs_task_definition" "quran_task" {
  family                   = "quran-microservice"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      =     "1024"
  memory                   = "970"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name = "quran-microservice"
    image = "861498464339.dkr.ecr.ap-south-1.amazonaws.com/quran-api-ms:1.0.0"
    cpu = 500
    memory = 500
    portMappings = [{
      containerPort = 8080
      hostPort = 8080
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.quran_logs.name
        awslogs-region        = "ap-south-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "quran_service" {
  name            = "quran-service"
  cluster         = aws_ecs_cluster.my_ecs_cluster.id
  task_definition = aws_ecs_task_definition.quran_task.arn
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private_subnet[*].id
    security_groups = [aws_security_group.ec2_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.quran_target_group.arn
    container_name   = "quran-microservice"
    container_port   = 8080
  }
}

