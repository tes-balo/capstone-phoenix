resource "azurerm_network_security_group" "cluster" {
  name        = "${var.project_name}-nsg"
  location = var.location
  resource_group_name = var.resource_group_name


  tags = {
    name    = "${var.project_name}-nsg"
    project = var.project_name


  }

}

resource "azurerm_network_security_rule" "http" {
  name = "${var.project_name}-allow-http"
  access              = "Allow"
  priority = 100
  direction = "Inbound"
  destination_port_range = "80"
  source_port_range = "*"
  source_address_prefix = "0.0.0.0/0"
  destination_address_prefix = "*"
  protocol          = "Tcp"
  resource_group_name = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.cluster.name

  description = "Rule for HTTPS traffic into the cluster"

}

resource "azurerm_network_security_rule" "https" {
  name = "${var.project_name}-allow-https"
  access = "Allow"
  priority = 110
  direction              = "Inbound"
  source_port_range = "*"
  destination_port_range = "443"
  source_address_prefix = "0.0.0.0/0"
  destination_address_prefix = "*"
  network_security_group_name = azurerm_network_security_group.cluster.name
  protocol          = "Tcp"
  resource_group_name = var.resource_group_name

  description = "Rule for HTTPS traffic into the cluster"


}

resource "azurerm_network_security_rule" "k3s_api" {
  name = "${var.project_name}-allow-control-node"
  access = "Allow"
  priority = 120
  direction = "Inbound"
  source_port_range = "*"
  source_address_prefix = var.my_ip
  destination_port_range = "6443"
  destination_address_prefix = "*"
  protocol          = "Tcp"
  network_security_group_name = azurerm_network_security_group.cluster.name
  resource_group_name = var.resource_group_name

  description = "Rule for HTTPS traffic into the control plane k8s node"

}

resource "azurerm_network_security_rule" "ssh" {
  name = "${var.project_name}-allow-ssh"
  resource_group_name = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.cluster.name

  access = "Allow"
  priority = 130
  protocol = "Tcp"
  direction = "Inbound"
  source_address_prefix = var.my_ip
  destination_address_prefix = "*"
  source_port_range = "*"
  destination_port_range = "22"

  description = "Rule for SSH traffic into the K8s nodes"

}

resource "azurerm_network_security_rule" "internal" {
  name = "${var.project_name}-allow-internal"
  resource_group_name = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.cluster.name

  access = "Allow"
  protocol = "*"
  priority = 140
  direction = "Inbound"
  source_port_range = "*"
  destination_port_range = "*"
  source_address_prefix = "10.0.1.0/24"
  destination_address_prefix = "*"

  description = "Rule for traffic within the subnet"

}