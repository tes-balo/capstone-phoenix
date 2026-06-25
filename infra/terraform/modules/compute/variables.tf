variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "ami_id" {
  description = "The ID of the AMI"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}

variable "security_group_id" {
  description = "The Security group of the instance"
  type        = string
}

variable "server_instance_type" {
  description = "The size of the server"
  type        = string
  default     = "t3.medium"

}

variable "worker_instance_type" {
  description = "The size of the workers"
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key_path" {
  description = "SSH public key location on control node"
  type        = string
}