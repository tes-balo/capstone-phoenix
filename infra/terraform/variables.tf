variable "region" {
  description = "Region of App"
  type        = string
}

variable "my_ip" {
  description = "My IP Address"
  type        = string

}

variable "project_name" {
  description = "Name of the project"
  type        = string

}

variable "ssh_public_key_path" {
  description = "Control node's public key"
  type        = string
}

variable "ami_id" {
  description = "ID of the AMI base image"
  type        = string
}

variable "server_instance_type" {
  description = "Size of the ec2 server (control node)"
  type        = string
}
variable "worker_instance_type" {
  description = "Size of each ec2 worker (worker nodes)"
  type        = string
}