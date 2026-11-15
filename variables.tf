variable "prefix" {
    type = string
    description = "short name used in front of every resource name"
    default = "threetier"
}


variable "location" {
  type = string
  description = "azure region"
  default = "spaincentral"
}


variable "vm_size" {
  type = string
  description = "size for the vms"
  default = "Standard_B1s"
}

variable "admin_username" {
  type = string
  description = "Linux admin user on every VM"
  default = "azureuser"
}

variable "ssh_public_key_path" {
  type = string
  description = "path to your public ip"
  default = "~/.ssh/id_rsa.pub"
}