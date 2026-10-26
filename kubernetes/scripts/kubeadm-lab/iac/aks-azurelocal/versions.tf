# Scenario C — AKS op Azure Local (AKS Arc), via de Azure Verified Module (AVM).
# Uitleg: CONCEPTS.md#aks-arc en STUDIEPLAN.md blok 8.
#
# Vereist een bestaand Azure Local-cluster met een custom location en een logical network.
# Buiten werk heb je dat niet: deze code is om te lezen, te valideren en op werk (waar toegestaan) te gebruiken.
# Microsoft noemt AKS Arc via Terraform een PREVIEW (oktober 2026).

terraform {
  required_version = ">= 1.10"

  required_providers {
    # De AVM-module v2.0.4 vereist azurerm ~> 4.0 en azapi ~> 2.12. Daarom hier NIET azurerm 5.x zoals in scenario B:
    # in één root-module moet iedereen het eens zijn over de providerversie.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }

  # Zelfde opzet als scenario B: state in Azure Storage met OIDC (andere key).
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "azapi" {}
