# Lessons learned

This is a note of the challenges, edge-cases and errors I encountered while building this project

* Azure B-series v1 capacity is unreliable across European regions
* B-series v2 is the current generation to target
* Quota increases are sometimes needed even when SKUs show as available
* prevent_deletion_if_contains_resources = false is essential for clean destroys
* Orphaned resources break subsequent destroys — the resource group force-delete saves you
* Azure resource group propagation delay can cause 404 errors on child resources immediately after creation. Running terraform apply a second time resolves it since the resource group is already fully propagated by then. Solution is to include a depends_on field inside each module block declared in the root main.tf like this:

```tf
module "network" {
  source = "./modules/network"

  resource_group_name = azurerm_resource_group.main.name
  project_name        = var.project_name
  location            = var.location

  depends_on = [azurerm_resource_group.main] // depends_on field
}
```
