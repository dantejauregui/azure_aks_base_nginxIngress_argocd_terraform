# Documentation for AKS Terraform found in: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster

# ---------- Variables ----------
variable "install_helmcharts" {
  description = "Install all Helmcharts via Helm"
  type        = bool
  default     = false
}

resource "azurerm_resource_group" "example" {
  name     = "aks-terraform-rg"
  location = "West Europe"
}

resource "azurerm_kubernetes_cluster" "example" {
  name                = "aks-terraform"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "aks-terraform"
  sku_tier            = "Free" # fine for dev/test

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }

  network_profile {
    network_plugin = "azure"
  }
}


output "client_certificate" {
  value     = azurerm_kubernetes_cluster.example.kube_config[0].client_certificate
  sensitive = true
}
output "kube_config" {
  value = azurerm_kubernetes_cluster.example.kube_config_raw

  sensitive = true
}
