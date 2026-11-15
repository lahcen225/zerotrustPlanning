output "vm_name" {
  value = azurerm_linux_virtual_machine.this.name
}

output "private_ip" {
  value = azurerm_network_interface.this.private_ip_address
}

output "public_ip" {
  description = "Public IP address, or null when public_ip = false"
  value       = var.public_ip ? azurerm_public_ip.this[0].ip_address : null
}