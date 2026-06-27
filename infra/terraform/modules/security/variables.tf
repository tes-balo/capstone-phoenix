variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
}


variable "my_ip" {
  description = "My IP address"
  type        = string

}

variable "resource_group_name" {
  description = "Name of the Resource group"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
}
