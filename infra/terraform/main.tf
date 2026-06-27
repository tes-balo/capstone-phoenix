resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

}



module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.main.name
  project_name        = var.project_name
  location            = var.location

}

module "security" {
  source = "./modules/security"

  resource_group_name = azurerm_resource_group.main.name
  project_name        = var.project_name
  location            = var.location
  my_ip               = var.my_ip

}

module "compute" {
  source = "./modules/compute"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  project_name        = var.project_name
  subnet_id           = module.network.subnet_id
  ssh_public_key_path = var.ssh_public_key_path
  server_vm_size      = var.server_vm_size
  worker_vm_size      = var.worker_vm_size
  nsg_id              = module.security.nsg_id

}
