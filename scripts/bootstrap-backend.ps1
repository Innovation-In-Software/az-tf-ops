<#
.SYNOPSIS
  Creates the Azure Storage account that holds Terraform state for the Orders
  solution. Lab 5.

.DESCRIPTION
  This is the one piece of infrastructure Terraform cannot manage for you: state
  has to live somewhere before there is any state. Every team bootstraps it once
  with a script like this and then leaves it alone.

  Creates:
    - resource group  rg-summit-tfstate
    - storage account stsummittfstate<suffix>   (versioning on, public access off)
    - blob container  tfstate

  Safe to run twice. Existing resources are left as they are.

.PARAMETER Suffix
  Your 2 to 6 character student suffix. Storage account names must be unique
  across all of Azure.

.PARAMETER Location
  Azure region. Defaults to eastus.

.EXAMPLE
  .\scripts\bootstrap-backend.ps1 -Suffix jr42
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,6}$')]
    [string]$Suffix,

    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'

$resourceGroup  = 'rg-summit-tfstate'
$storageAccount = "stsummittfstate$Suffix"
$container      = 'tfstate'

Write-Host "Bootstrapping Terraform state backend" -ForegroundColor Cyan
Write-Host "  resource group:  $resourceGroup"
Write-Host "  storage account: $storageAccount"
Write-Host "  container:       $container"
Write-Host "  location:        $Location"
Write-Host ""

# --- confirm we are signed in and on the right subscription -----------------
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Not signed in. Run 'az login' first."
}
Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Yellow
Write-Host ""

# --- resource group ---------------------------------------------------------
az group create `
    --name $resourceGroup `
    --location $Location `
    --tags solution=orders owner=ops-team managed_by=bootstrap purpose=tfstate `
    --output none
Write-Host "resource group ready" -ForegroundColor Green

# --- storage account --------------------------------------------------------
$exists = az storage account check-name --name $storageAccount --query nameAvailable -o tsv
if ($exists -eq 'true') {
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --tags solution=orders owner=ops-team managed_by=bootstrap purpose=tfstate `
        --output none
    Write-Host "storage account created" -ForegroundColor Green
}
else {
    # The name is taken. It might be yours from a previous run, or somebody
    # else's entirely.
    $mine = az storage account show --name $storageAccount --resource-group $resourceGroup --output json 2>$null
    if (-not $mine) {
        throw "Storage account name '$storageAccount' is taken by someone else. Pick a different suffix."
    }
    Write-Host "storage account already exists, reusing it" -ForegroundColor Green
}

# --- blob versioning: cheap insurance against a bad state write -------------
az storage account blob-service-properties update `
    --account-name $storageAccount `
    --resource-group $resourceGroup `
    --enable-versioning true `
    --output none
Write-Host "blob versioning enabled" -ForegroundColor Green

# --- container --------------------------------------------------------------
# Role assignments can take a minute to reach the data plane, so retry.
$created = $false
foreach ($attempt in 1..6) {
    try {
        az storage container create `
            --name $container `
            --account-name $storageAccount `
            --auth-mode login `
            --output none 2>$null
        $created = $true
        break
    }
    catch {
        Write-Host "  waiting for storage permissions to propagate (attempt $attempt of 6)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }
}
if (-not $created) {
    throw "Could not create the container. Confirm you have Owner or Storage Blob Data Contributor on the subscription, then rerun."
}
Write-Host "container ready" -ForegroundColor Green

# --- what to paste into backend.tf ------------------------------------------
Write-Host ""
Write-Host "Done. Put this in environments/<env>/backend.tf:" -ForegroundColor Cyan
Write-Host ""
Write-Host @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$resourceGroup"
    storage_account_name = "$storageAccount"
    container_name       = "$container"
    key                  = "orders-dev.terraform.tfstate"
  }
}
"@
Write-Host ""
Write-Host "Use a different key per environment: orders-dev..., orders-prod..., orders-legacy..." -ForegroundColor Yellow
