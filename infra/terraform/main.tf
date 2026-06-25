module "network" {
  source = "./modules/network"

  project_name = var.project_name
  region       = var.region
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  my_ip        = var.my_ip

}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  ami_id               = var.ami_id
  subnet_id            = module.network.subnet_id
  security_group_id    = module.security.security_group_id
  ssh_public_key_path  = var.ssh_public_key_path
  server_instance_type = var.server_instance_type
  worker_instance_type = var.worker_instance_type

}