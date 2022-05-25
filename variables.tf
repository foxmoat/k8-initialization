variable "resource_group_name_prefix" {
  default       = "rg"
  description   = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "resource_group_location" {
  default       = "eastus"
  description   = "Location of the resource group."
}

#variable "resource_depends_on" {
#  type    = any
#  default = null
#}

variable "vmlist" {
  type = map(object({
    hostname = string
    private_ip_address = string
    public_ip_address = bool
  }))
  default = {
    vm1 ={
      hostname = "k8-master1"
      private_ip_address = "10.0.1.10"
      public_ip_address = true
    },
    vm2 = {
      hostname = "k8-node1"
      private_ip_address = "10.0.1.11"
      public_ip_address = false
    }
    vm3 = {
      hostname = "k8-node2"
      private_ip_address = "10.0.1.12"
      public_ip_address = false
    }
    vm4 = {
      hostname = "k8-node3"
      private_ip_address = "10.0.1.13"
      public_ip_address = false
    }
  }
}