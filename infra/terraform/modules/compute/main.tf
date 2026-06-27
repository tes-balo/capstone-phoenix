################################ CONTROL PLANE ###################################


resource "azurerm_public_ip" "control_plane" {
  name                = "${var.project_name}-control-plane-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "control_plane" {
  name                = "${var.project_name}-control-plane-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.control_plane.id
  }
}

resource "azurerm_network_interface_security_group_association" "control_plane" {
  network_interface_id      = azurerm_network_interface.control_plane.id
  network_security_group_id = var.nsg_id
}


resource "azurerm_linux_virtual_machine" "control_plane" {
  name                  = "${var.project_name}-control-plane-vm"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.server_vm_size
  network_interface_ids = [azurerm_network_interface.control_plane.id]

  admin_username                  = "tes"
  disable_password_authentication = true

  admin_ssh_key {
    public_key = file(var.ssh_public_key_path)
    username   = "tes"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

################################### WORKER(S) ###################################

resource "azurerm_public_ip" "worker" {
  count = 2

  name                = "${var.project_name}-worker-${count.index}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
  sku                 = "Standard"

}

resource "azurerm_network_interface" "worker" {
  count = 2

  name                = "${var.project_name}-worker-${count.index}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.worker[count.index].id
  }

}


resource "azurerm_network_interface_security_group_association" "worker" {
  count = 2

  network_interface_id      = azurerm_network_interface.worker[count.index].id
  network_security_group_id = var.nsg_id


}



resource "azurerm_linux_virtual_machine" "worker" {
  count = 2

  name                  = "${var.project_name}-worker-${count.index}-vm"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.worker_vm_size
  network_interface_ids = [azurerm_network_interface.worker[count.index].id]

  admin_username                  = "tes"
  disable_password_authentication = true

  admin_ssh_key {
    public_key = file(var.ssh_public_key_path)
    username   = "tes"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

}



# TODO: Use Launch templates, auto scaling groups  and user data to refactor architecture
# Check TODO.md

#TODO: use a bastion host or VPN and keep workers private.
