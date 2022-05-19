output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  value = [
    for myterraformvm in azurerm_linux_virtual_machine.myterraformvm : myterraformvm.public_ip_address
  ]
  
}
