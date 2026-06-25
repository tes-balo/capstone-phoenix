resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    name    = "${var.project_name}-key-pair"
    project = "${var.project_name}"
  }
}

resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.server_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.main.key_name

  tags = {
    name    = "${var.project_name}-server"
    project = "${var.project_name}"
  }

}

resource "aws_instance" "worker" {
  ami                    = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.main.key_name
  count                  = 2

  tags = {
    name    = "${var.project_name}-worker"
    project = "${var.project_name}"
  }

}


# TODO: Use Launch templates, auto scaling groups  and user data to refactor architecture
# Check TODO.md