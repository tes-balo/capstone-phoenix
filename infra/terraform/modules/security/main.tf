resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-sg"
  description = "Security group for k3s cluster nodes"
  vpc_id      = var.vpc_id

  tags = {
    name    = "${var.project_name}-sg"
    project = var.project_name
  }

}

resource "aws_security_group_rule" "http" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "https" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "k3s_api" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}/32"]

}

resource "aws_security_group_rule" "ssh" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}/32"]
}

resource "aws_security_group_rule" "internal" {
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["10.0.1.0/24"]
}