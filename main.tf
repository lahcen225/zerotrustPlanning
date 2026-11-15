resource "azurerm_resource_group" "rg" {
    name = "${var.prefix}-rg"
    location = var.location
    tags = local.common_tags
}


module "network" {
    source = "./modules/network"

    name = "${var.prefix}-vnet"
    resource_group_name = azurerm_resource_group.rg.name
    location = azurerm_resource_group.rg.location
    address_space = local.vnet_cidr
    subnets = {for tier in local.tiers : tier => local.ip_plan[tier]}
    tags = local.common_tags
  
}


