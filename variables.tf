## For Resource Group Block 
variable "rg_name" {
  default = "Terraform_Project"
}
variable "rg_location" {
  default = "East US"
}

## For Virtual Network Block
variable "vnet_name" {
  default = "terra_virtual_network"
}

### For Subnets
## For Web App Subnet
variable "webappsub_name" {
  default = "webappsubnet"
}

## For Logic App Subnet
variable "logicappsub_name" {
  default = "logicappsubnet"
}

## For Database Subnet
variable "databasesub_name" {
  default = "databasesubnet"
}

## For Public IP
variable "public_ip_name" {
  default = "publicip"
}

## Load Balancer 
variable "loadbalancer_name" {
  default = "vmss_loadbalancer"
}
variable "loadbalancer_frontendpool" {
  default = "lb_frontendpool"
}
variable "loadbalancer_backendpool" {
  default = "lb_backendpool"
}
variable "loadbalancer_probe" {
  default = "lb_http_probe"
}
variable "loadbalancer_httprule" {
  default = "lb_http_rule"
}

#for VMSS
variable "windowsvmss_name" {
  default = "webappvmss"
}
variable "adminvmss_username" {
  default = "windowsadmin"
}
variable "adminvmss_password" {
  default = "Windowsuser@1234"
  type = string
  sensitive = true
}

#NSG
variable "nsg_logic" {
  default = "nsglogicsubnet"
}

variable "nsg_database" {
  default = "nsgdatabase"
}
# NIC
variable "nic_logicapp" {
  default = "logicapp_nic"
} 

# VM
variable "windowsvm_name" {
  default = "logicappvm"
}
variable "adminvm_username" {
  default = "windowsadmin"
}
variable "adminvm_password" {
  default = "Windowsuser@1234"
  type = string
  sensitive = true
}

variable "mysql_name" {
  default = "terrasql"
}
variable "mysql_admin_user" {
  default = "adminuser"
}
variable "mysql_admin_password" {
  default = "Sqluser@1234"
}
