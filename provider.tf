terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
    helm = {
      source  = "hashicorp/helm",
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
  }
}

provider "azurerm" {
  features {}
}
provider "kubernetes" {
  config_path = pathexpand("~/.kube/aks-dev")
}
provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/aks-dev")
  }
}
