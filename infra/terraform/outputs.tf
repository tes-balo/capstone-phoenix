# output "my_ip" {
#     description = "My IP Address"
#     value = "102.91.78.91"
# }

# output "project_name" {
#     description = "Name of the project"
#     value = "capstone-phoenix"
# }

# output "ssh_public_key_path" {
#     description = "Path of public key on control node"
#     value = "~/.ssh/capstone-phoenix.pub"
# }

# output "region" {
#     description = "Region of the App"
#     value = "eu-north-1"
# }

output "control_plane_public_ip" {
  description = "Public IP address of the master node"
  value       = module.compute.control_plane_public_ip
}


output "control_plane_private_ip" {
  description = "Private address of the master node"
  value       = module.compute.control_plane_private_ip
}

output "worker_public_ip" {
  description = "Public IP of the worker node"
  value       = module.compute.worker_public_ip
}
