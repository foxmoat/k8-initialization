resource "random_pet" "rg-name" {
  prefix    = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  name      = random_pet.rg-name.id
  location  = var.resource_group_location
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
  name                = "k8Vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
  name                 = "k8Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
  name                = "k8-master1-publicIp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = "k8-master1-publicip"
}

data "azurerm_public_ip" "myterraformpublicip" {
  name                = azurerm_public_ip.myterraformpublicip.name
  resource_group_name = azurerm_resource_group.rg.name
  depends_on          = [azurerm_linux_virtual_machine.myterraformvm["vm1"]]
}

data "azurerm_key_vault" "azurekv" {
  name = "k8-init-keyvault"
  resource_group_name = "k8-initialization"
}

data "azurerm_key_vault_secret" "azureuserpub" {
  name = "azureuserpub"
  key_vault_id = data.azurerm_key_vault.azurekv.id
}

data "azurerm_key_vault_secret" "azureuserpriv" {
  name = "azureuserpriv"
  key_vault_id = data.azurerm_key_vault.azurekv.id
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "k8NetworkSecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "k8-static-nic" {
  for_each = var.vmlist
  name                = "${each.value.hostname}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "k8-nic-configuration"
    subnet_id                     = azurerm_subnet.myterraformsubnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip_address
    public_ip_address_id          = "${each.value.public_ip_address == true ? azurerm_public_ip.myterraformpublicip.id : null}" 
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  for_each = var.vmlist
  network_interface_id      = azurerm_network_interface.k8-static-nic[each.key].id
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "diag${random_id.randomId.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "myterraformvm" {
  for_each = var.vmlist
  name                  = each.value.hostname
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.k8-static-nic[each.key].id]
  size                  = "Standard_DS2_v2"
  custom_data           = filebase64("k8-scripts/k8-install.yml")

  os_disk {
    name                 = "${each.value.hostname}-myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = each.value.hostname
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = "${data.azurerm_key_vault_secret.azureuserpub.value}"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}

#resource "time_sleep" "wait_for_myterraformvm_vm1" {
#  depends_on      = [azurerm_linux_virtual_machine.myterraformvm["vm1"]]
#  create_duration = "300s"
#}

resource "null_resource" "upload" {
  connection {
    host = "${azurerm_public_ip.myterraformpublicip.fqdn}" #"${data.azurerm_public_ip.myterraformpublicip.ip_address}" #https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/public_ip#example-usage-retrieve-the-dynamic-public-ip-of-a-new-vm
    type = "ssh"
    user = "azureuser"
    private_key = "${data.azurerm_key_vault_secret.azureuserpriv.value}"
  }

  provisioner "file" {
    content     = "${data.azurerm_key_vault_secret.azureuserpriv.value}"
    destination = "/home/azureuser/.ssh/id_rsa"
  }

  provisioner "file" {
    source     = "k8-scripts/k8-init.sh"
    destination = "/home/azureuser/k8-init.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/azureuser/.ssh/id_rsa",
      "chmod 700 /home/azureuser/k8-init.sh",
      "sudo cp /home/azureuser/.ssh/id_rsa /root/.ssh",
      "sudo /home/azureuser/k8-init.sh",
    ]
  }

  depends_on = [azurerm_linux_virtual_machine.myterraformvm["vm1"]]
}
