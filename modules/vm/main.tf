resource "azurerm_public_ip" "this" {
  count = var.public_ip ? 1 : 0


  name = "${var.name}-pip"
  location = var.location
  resource_group_name = var.resource_group_name
  allocation_method = "Static"
  sku = "Standard"
  tags = var.tags

}


resource "azurerm_network_interface" "this" {
  name = "${var.name}-nic"
  location = var.location
  resource_group_name = var.resource_group_name
  tags = var.tags

  ip_configuration {
    name = "internal"
    subnet_id = var.subnet_id
    private_ip_address_allocation = "static"
    private_ip_address = var.private_ip
    public_ip_address_id = var.public_ip ? azurerm_public_ip.this[0] : null #dus als die enabled word die bovenste code blokk aangemaakt en dan ga je hier na  die index 0 het maakt maar 1 altijf is dus altijd index null maar als die niet enbaled geefje null terug
  }

}


resource "azurerm_linux_virtual_machine" "this" {
    name = "${var.name}-vm"
    location = var.location
    resource_group_name = var.resource_group_name
    size = var.vm_size
    admin_username = var.admin_username
    network_interface_ids = [azurerm_network_interface.this.id]
    tags = var.tags

    admin_ssh_key {
      username = var.admin_username
      public_key = var.ssh_public_key
    }

    os_disk {
      caching = "ReadWrite"
      storage_account_type = "Standard_LRS"
    }

    source_image_reference {
      publisher = "Canonical"
      offer = "ubuntu-24_04-lts"
      sku = "server"
      version = "lastest"
    }

    custom_data = base64decode(var.custom_data)
  
}