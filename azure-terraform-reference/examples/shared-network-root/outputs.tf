output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "subnet_ids" {
  value = {
    for name, subnet in azurerm_subnet.this : name => subnet.id
  }
}
