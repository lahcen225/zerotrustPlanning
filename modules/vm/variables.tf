variable "name" {
  type        = string
  description = "Base name; resources become <name>-vm, <name>-nic, <name>-pip"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the VM"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "subnet_id" {
  type        = string
  description = "Subnet for the NIC"
}

variable "private_ip" {
  type        = string
  description = "Fixed private IP, must be inside the subnet"
}

variable "public_ip" {
  type        = bool
  description = "true = also create a public IP for this VM"
  default     = false
}

variable "vm_size" {
  type        = string
  description = "VM size"
}


variable "admin_username" {
  type        = string
  description = "Linux admin user"
}


variable "ssh_public_key" {
  type        = string
  description = "Contents of the public SSH key (not the path)"
}

variable "custom_data" {
  type        = string
  description = "Startup script (plain text, the module base64-encodes it)"
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Tags for every resource"
  default     = {}
}