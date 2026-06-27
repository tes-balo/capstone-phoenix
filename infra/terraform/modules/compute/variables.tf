variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}


variable "location" {
  description = "Azure location"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string

}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}

variable "server_vm_size" {
  description = "The size of the server"
  type        = string
  # default     = ""

}

variable "worker_vm_size" {
  description = "The size of the workers"
  type        = string
  # default     = ""
}

variable "ssh_public_key_path" {
  description = "Control node's public key"
  type        = string
}

variable "nsg_id" {
  description = "The ID of the Network security group"
  type = string
}

# variable "vnet_id" {
#   description = "The ID of the network "

# }