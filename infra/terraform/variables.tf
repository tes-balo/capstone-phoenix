variable "location" {
  description = "Location of App"
  type        = string
  default = "westeurope"
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

variable "server_vm_size" {
  description = "Size of the virtual machine (control node)"
  type        = string
}
variable "worker_vm_size" {
  description = "Size of each virtual machine (worker nodes)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type = string
}

variable "subscription_id" {
  description = "ID of the Azure subscription"
  type = string

}