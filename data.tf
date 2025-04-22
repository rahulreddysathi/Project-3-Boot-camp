data "azurerm_key_vault" "passwordkey" {
  name                = "passwordkeyv"
  resource_group_name = "tfstaterg"
}

data "azurerm_key_vault_secret" "adminvm_password" {
  name         = "vmadmin"
  key_vault_id = data.azurerm_key_vault.passwordkey.id
}

data "azurerm_key_vault_secret" "adminvmss_password" {
  name         = "vmssadmin"
  key_vault_id = data.azurerm_key_vault.passwordkey.id
}
