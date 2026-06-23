resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        name = "${var.project_name}-vpc"
        project = var.project_name
    }
    }

resource "aws_subnet" "main" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "${var.region}a"
    map_public_ip_on_launch = true

    tags = {
        name = "${var.project_name}-subnet"
        project = var.project_name
    }
}

