# Scenario B — AKS in Azure, uitgerold door GitHub Actions met OIDC (geen secrets).
# Uitleg: CONCEPTS.md#aks, CONCEPTS.md#oidc-federatie, STUDIEPLAN.md blok 8.

terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10" # gecontroleerd op 5.10.0 (oktober 2026); 6.0 heeft een upgrade-guide = breaking changes
    }
  }

  # Remote state in een storage account (gemaakt door bootstrap.sh).
  # De waarden komen bij init:  terraform init -backend-config=backend.hcl   (of via -backend-config=... in de workflow)
  # Inloggen bij de state gaat met Entra ID + OIDC (ARM_USE_OIDC=true, ARM_USE_AZUREAD=true), zonder storage key.
  backend "azurerm" {}
}

# Geen inloggegevens in de code: de workflow zet ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# en ARM_USE_OIDC=true. Lokaal werkt het ook na 'az login'.
provider "azurerm" {
  features {}
}
