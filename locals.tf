locals {
  common_tags = {
    project = "3tier-walkthroug"
    managed_by = "terraform"
  }

  vnet_cidr = "10.0.0.0/16"

  ip_plan = {
    web = "10.0.1.0/24"
    app = "10.0.2.0/24"
    db = "10.0.3.0/24"
  }

  tiers = ["web"]
}