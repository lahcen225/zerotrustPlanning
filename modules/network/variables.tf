variable "name" {
    type = string
    description = "Name of the vnet"
}


variable "resource_group_name" {
  type = string
  description = "Resource group for the VNet"
}

variable "location" {
  type = string
  description = "Azure Region"
}

variable "address_space" {
  type = string
  description = "cidr of the whole network"
}

variable "subnets" {
  type = map(string)
  description = "subnet name => CIDR, e.g. { web = \"10.0.1.0/24"

}


variable "tags" {
  type = map(string)
  description = "tags for the vnet"
  default = []
}