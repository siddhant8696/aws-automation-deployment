provider "aws" {
	region = "us-east-1"
}

resource "aws_vpc" "main" {
	cidr_block = "10.0.0.0/16"

	tags ={
		Name= "aws-automation-deployment-vpc"
	}
}


resource "aws_subnet" "public" {
	vpc_id		=	aws_vpc.main.id
	cidr_block	=	"10.0.1.0/24"
	map_public_ip_on_launch =	true

	tags =  {
	Name = "aws-autoamtion-deployment-public-subnet"
}
}

resource "aws_internet_gateway" "main" {
vpc_id = aws_vpc.main.id

tags = {
Name = "aws-automation-deployment-igw"
}
}

resource "aws_route_table" "public" {
vpc_id = aws_vpc.main.id

route {
 cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.main.id
}

tags = {
Name = "aws_automation-deployment-public-rt"
}
}

resource "aws_route_table_association" "public" {
subnet_id = aws_subnet.public.id
route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
	Name = "aws-automation-deployment-private-subnet"
  }
}

resource "aws_ecr_repository" "app"{
	name="aws-automation-deployment-app"

	tags = {
	  Name = "aws-automation-deployment-app"
	}
}

output "ecr_repository_url"{
	value = aws_ecr_repository.app.repository_url
}

resource "aws_ecs_cluster" "main" {
  name = "aws-automation-deployment-cluster"

  tags = {
	Name ="aws-automation-deployment-cluster"
  }
}

resource "aws_iam_role" "ecs_task_execution" {
	name = "aws-automation-deployment-ecs-execution-role"

	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [
			{
				Action = "sts:AssumeRole"
				Effect = "Allow"
				Principal = {
					Service = "ecs-tasks.amazonaws.com"
				}
			}
		]
	})
  
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
	role = aws_iam_role.ecs_task_execution.name
	policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
	family = "aws-automation-deployment-task"
	requires_compatibilities = ["FARGATE"]
	network_mode = "awsvpc"
	cpu = "256"
	memory = "512"
	execution_role_arn = aws_iam_role.ecs_task_execution.arn

	container_definitions = jsonencode([
		{
			name = "aws-automation-deployment-app"
			image ="${aws_ecr_repository.app.repository_url}:latest"
			essential = true
			portMappings = [
				{
					containerPort = 8080
					hostPort = 8080
				}
			]
		}
	])
  
}

resource "aws_subnet" "public2" {
	vpc_id = aws_vpc.main.id
	cidr_block = "10.0.3.0/24"
	availability_zone = "us-east-1a"
	map_public_ip_on_launch = true

	tags = {
	  Name = "aws-automation-deployment-public-subnet-2"
	}
  
}

resource "aws_route_table_association" "public2" {
	subnet_id =  aws_subnet.public2.id
	route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
	name = "aws-automation-deployment-alb-sb"
	description = "Allow inboud HTTP traffic to the ALB"
	vpc_id = aws_vpc.main.id

	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
	  Name = "aws-automation-deployment-alb-sg"
	}
  
}

resource "aws_lb" "main" {
	name = "aws-automation-deployment-alb"
	internal = false
	load_balancer_type = "application"
	security_groups = [ aws_security_group.alb.id ]
	subnets = [ aws_subnet.public.id, aws_subnet.public2.id ]

	tags = {
	  Name = "aws-automation-deployment-alb"
	}
}

resource "aws_lb_target_group" "app" {
	name = "aws-automation-deployment-tg"
	port = 8080
	protocol = "HTTP"
	vpc_id = aws_vpc.main.id
	target_type = "ip"

	health_check {
	  path = "/"
	}

	tags = {
	  Name = "aws-automation-deployment-tg"
	}
}

resource "aws_lb_listener" "http" {
	load_balancer_arn = aws_lb.main.arn
	port = 80
	protocol = "HTTP"

	default_action {
	  type = "forward"
	  target_group_arn = aws_lb_target_group.app.arn
	}
  
}

resource "aws_security_group" "ecs_tasks" {
	name = "aws-automation-deployment-ecs-sg"
	description = "Allow inbound traffics from the ALB only"
	vpc_id = aws_vpc.main.id

	ingress  {
		from_port = 8080
		to_port = 8080
		protocol = "tcp"
		security_groups = [aws_security_group.alb.id]
	}

	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
	  Name = "aws-automation-deployment-ecs-sg"
	}
}

resource "aws_ecs_service" "app" {
  name            = "aws-automation-deployment-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id, aws_subnet.public2.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "aws-automation-deployment-app"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}


output "alb_dns_name" {
	value = aws_lb.main.dns_name
  
}

resource "aws_iam_user" "github_actions" {
	name = "aws-automation-deployment-github-actions"
  
}

resource "aws_iam_user_policy" "github_actions" {
	name = "aws-automation-deployment-git-actions-policy"
	user = aws_iam_user.github_actions.name

	policy = jsonencode({
		Version = "2012-10-17"
		Statement = [
			{
				Effect ="Allow"
				Action = [
					"ecr:GetAuthorizationToken",
					"ecr:BatchCheckLayerAvailability",
					"ecr:GetDownloadIrlForLayer",
					"ecr:BatchGetImage",
					"ecr:PutImage",
					"ecr:InitiateLayerUpload",
					"ecr:UploadLayerPart",
					"ecr:CompleteLayerUpload"
				]
			Resource = "*"
			},
			{
				Effect = "Allow"
				Action = [
					"ecs:UpdateService",
					"ecs:DescribeService"
				]
				Resource = "*"
			}
		]
})
  
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

output "github_actions_access_key_id" {
	value = aws_iam_access_key.github_actions.id  
}

output "github_actions_secret_access_key" {
	value = aws_iam_access_key.github_actions.secret
	sensitive = true
  
}