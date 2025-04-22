terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">=3.60.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstaterg"
    storage_account_name = "terrastatefilestore"
    container_name       = "statefileterraprojectv1"
    key                  = "terraform.tfstate"
  }
}
provider "azurerm" {
    
    subscription_id = "5599caf4-da21-4b99-ab26-322c7c0e36f9"
   skip_provider_registration = true
   features {}
}
## Tags 
locals {
  common_tags = {
    Project= "3Tire_Terra_Project "
  }

  env_tags = {
    dev = {
      Environment = "Development"
    }
    staging = {
      Environment = "Staging"
    }
    prod = {
      Environment = "Production"
    }
  }
  tags = merge(
    local.common_tags,
    lookup(local.env_tags, terraform.workspace, {})
  )
}

######

## Resource Group Block
resource "azurerm_resource_group" "resource_group" {
  name = var.rg_name
  location = var.rg_location
  tags = local.tags
}

## Virtual Network Block
resource "azurerm_virtual_network" "virtual_network" {
  name = var.vnet_name
  address_space = ["192.168.0.0/16"]
  location = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  tags = local.tags
}
### Subnet

## Subnet for Webapp Tire
resource "azurerm_subnet" "webapp_subnet" {
  name = var.webappsub_name
  resource_group_name = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes = ["192.168.1.0/24"]
}

## Subnet for Logical Application Tire
resource "azurerm_subnet" "logicapp_subnet" {
  name = var.logicappsub_name
  resource_group_name = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes = ["192.168.2.0/24"]
}

## Subnet for Database Tire
resource "azurerm_subnet" "database_subnet" {
  name                 = var.databasesub_name
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["192.168.3.0/24"]
  delegation {
    name = "dbdelegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}
#############
## Public Ip
resource "azurerm_public_ip" "public_ip" {
  name = var.public_ip_name
  location = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method = "Static"
  sku = "Standard"
  tags = local.tags
}

##Load Balancer

resource "azurerm_lb" "load_balancer" {
  name                = var.loadbalancer_name
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = var.loadbalancer_frontendpool
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
  depends_on = [ azurerm_public_ip.public_ip ]
  tags = local.tags
}

resource "azurerm_lb_backend_address_pool" "backend_pool" {
  name                = var.loadbalancer_backendpool
  loadbalancer_id     = azurerm_lb.load_balancer.id
  ##resource_group_name = azurerm_resource_group.resource_group.name
  depends_on = [ azurerm_lb.load_balancer ]
}

resource "azurerm_lb_probe" "probe" {
  name                = var.loadbalancer_probe
  ##resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.load_balancer.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  depends_on = [ azurerm_lb_backend_address_pool.backend_pool ]
}

resource "azurerm_lb_rule" "http" {
  name                           = var.loadbalancer_httprule
 ## resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.load_balancer.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  #frontend_ip_configuration_name = "frontend_ip_config"
  frontend_ip_configuration_name = var.loadbalancer_frontendpool
  ##backend_address_pool_id        = azurerm_lb_backend_address_pool.backend_pool.id
  probe_id                       = azurerm_lb_probe.probe.id
  depends_on = [ azurerm_lb_probe.probe ]
}


## VMSS

resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                = var.windowsvmss_name
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "Standard_DS1_v2"
  instances           = 2
  admin_username      = var.adminvmss_username
 # admin_password      = var.adminvmss_password
  admin_password = data.azurerm_key_vault_secret.adminvmss_password.value
  computer_name_prefix = "web"
  zones = terraform.workspace == "prod" ? ["1", "2", "3"] : null

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  upgrade_mode = "Automatic"

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "vmss-ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.webapp_subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.backend_pool.id]
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(<<-EOF
<powershell>
  # Install IIS
  Install-WindowsFeature -name Web-Server -IncludeManagementTools

  # Install Chocolatey
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
  iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

  # Refresh environment variables (optional)
  refreshenv

  # Install Apache HTTP Server
  choco install apache-httpd -y

  # Start Apache service (may need path adjustments depending on version)
  & "C:\\tools\\Apache24\\bin\\httpd.exe" -k install
  Start-Service Apache2.4
</powershell>
EOF
)

  tags = local.tags
  depends_on = [azurerm_lb.load_balancer, azurerm_resource_group.resource_group, azurerm_subnet.webapp_subnet, azurerm_public_ip.public_ip]
}

# Auto Scaling 
resource "azurerm_monitor_autoscale_setting" "vmss_autoscale" {
  name                = "vmss-autoscale"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.vmss.id

  profile {
    name = "autoscale-profile"

    capacity {
      minimum = "2"
      maximum = "5"
      default = "2"
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  enabled = true
  tags    = local.tags
}

####Tire 2

### NSG for LogicApp subnet
resource "azurerm_network_security_group" "logic_nsg" {
  name                = var.nsg_logic
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  security_rule {
    name                       = "AllowWebAppSubnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "192.168.1.0/24"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "AllowDatabaseSubnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "192.168.3.0/24"
    source_port_range          = "*" 
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "DenyInternetIn"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "Internet"
    source_port_range          = "*" 
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  tags = local.tags
  depends_on = [ azurerm_virtual_network.virtual_network,azurerm_subnet.logicapp_subnet, azurerm_subnet.database_subnet, azurerm_subnet.webapp_subnet ]
}

resource "azurerm_subnet_network_security_group_association" "logic_subnet_nsg_assoc" {
  subnet_id                 = azurerm_subnet.logicapp_subnet.id
  network_security_group_id = azurerm_network_security_group.logic_nsg.id
  depends_on = [ azurerm_network_security_group.logic_nsg ]
}

## Logic App Windows VM
###NIC for VM
resource "azurerm_network_interface" "logic_vm_nic" {
  name                = var.nic_logicapp
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.logicapp_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = null
  }

  tags = local.tags
}

## Logic App VM
resource "azurerm_windows_virtual_machine" "logic_vm" {
  name                  = var.windowsvm_name
  location              = azurerm_resource_group.resource_group.location
  resource_group_name   = azurerm_resource_group.resource_group.name
  size                  = "Standard_DS1_v2"
  admin_username        = var.adminvm_username
  #admin_password        = var.adminvm_password
  admin_password = data.azurerm_key_vault_secret.adminvm_password.value
  network_interface_ids = [azurerm_network_interface.logic_vm_nic.id]
  zone = terraform.workspace == "prod" ? "1" : null
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  tags = local.tags
  depends_on = [ azurerm_network_interface.logic_vm_nic ]
}

###Tire 3
##NSG for Data subnet

resource "azurerm_network_security_group" "database_nsg" {
  name                = var.nsg_database
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  security_rule {
    name                       = "AllowLogicAppSubnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "192.168.2.0/24"
    destination_address_prefix = "*"
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "AllowWebAppSubnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "192.168.1.0/24"
    destination_address_prefix = "*"
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  security_rule {
    name                       = "DenyInternetIn"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
    destination_port_range     = "*"
    source_port_range          = "*"
  }

  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "database_subnet_nsg_assoc" {
  subnet_id                 = azurerm_subnet.database_subnet.id
  network_security_group_id = azurerm_network_security_group.database_nsg.id
}

##Dns

resource "azurerm_private_dns_zone" "mysql_dns_zone" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql_dns_link" {
  name                  = "mysql-dns-link"
  resource_group_name   = azurerm_resource_group.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.virtual_network.id
}

resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = var.mysql_name
  resource_group_name    = azurerm_resource_group.resource_group.name
  location               = azurerm_resource_group.resource_group.location
  administrator_login    = var.mysql_admin_user
  administrator_password = var.mysql_admin_password
  sku_name               = "B_Standard_B1ms"
  version                = "8.0.21"
  zone = terraform.workspace == "prod" ? "1" : null

  backup_retention_days           = 7
  geo_redundant_backup_enabled    = false

  delegated_subnet_id             = azurerm_subnet.database_subnet.id
  private_dns_zone_id             = azurerm_private_dns_zone.mysql_dns_zone.id

  storage {
    size_gb = 32
  }

  tags = local.tags
  depends_on = [ azurerm_private_dns_zone_virtual_network_link.mysql_dns_link ]
}
