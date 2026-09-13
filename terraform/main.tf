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