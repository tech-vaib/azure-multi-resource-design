# Replace this example module source with the team's reviewed AKS module.
# The AKS module receives subnet_id; it must not create/manage the VNet or subnet.
module "aks" {
  source = "../../modules/aks"

  location            = var.location
  resource_group_name = var.resource_group_name
  name                = var.aks_name
  kubernetes_version  = var.kubernetes_version
  subnet_id           = var.subnet_id
}
