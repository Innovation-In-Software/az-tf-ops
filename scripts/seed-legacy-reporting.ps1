<#
.SYNOPSIS
  Stands up the "legacy" reporting environment for the Lab 9 import exercise.

.DESCRIPTION
  Everything here is created with the Azure CLI, deliberately, to simulate an
  environment somebody built by hand in the portal three years ago and never
  documented. It is NOT managed by Terraform, and that is the point: Lab 9 is
  about bringing it under management without deleting and rebuilding it.

  The rough edges are intentional. Do not tidy them up:
    - tag keys use inconsistent casing ("Owner", "CostCentre", "env")
    - the storage account allows TLS 1.0, which nobody would choose today
    - the resource group has no managed_by tag, so nothing warns you off it
    - names follow no convention at all

  Creates in rg-legacy-reporting:
    - storage account  stsmtlegacy<suffix>  with container  reports
    - virtual network  legacy-reporting-vnet  with subnet  default

  Safe to run twice.

.PARAMETER Suffix
  Your 2 to 6 character student suffix.

.PARAMETER Location
  Azure region. Defaults to eastus.

.EXAMPLE
  .\scripts\seed-legacy-reporting.ps1 -Suffix jr42
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,6}$')]
    [string]$Suffix,

    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'

$resourceGroup  = 'rg-legacy-reporting'
$storageAccount = "stsmtlegacy$Suffix"
$container      = 'reports'
$vnet           = 'legacy-reporting-vnet'
$subnet         = 'default'

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) { throw "Not signed in. Run 'az login' first." }

Write-Host "Seeding the legacy reporting environment" -ForegroundColor Cyan
Write-Host "  subscription: $($account.name)"
Write-Host "  (pretend a colleague built this in the portal in 2023)"
Write-Host ""

# --- resource group. Note the tag keys: nobody agreed on a convention. -------
az group create `
    --name $resourceGroup `
    --location $Location `
    --tags Owner=dave.reporting CostCentre=FIN-2019 env=Production `
    --output none
Write-Host "resource group $resourceGroup" -ForegroundColor Green

# --- storage account, with settings a 2023 default would have given you ------
$available = az storage account check-name --name $storageAccount --query nameAvailable -o tsv
if ($available -eq 'true') {
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location $Location `
        --sku Standard_GRS `
        --kind StorageV2 `
        --access-tier Cool `
        --min-tls-version TLS1_0 `
        --tags Owner=dave.reporting env=Production `
        --output none
    Write-Host "storage account $storageAccount" -ForegroundColor Green
}
else {
    $mine = az storage account show --name $storageAccount --resource-group $resourceGroup --output json 2>$null
    if (-not $mine) { throw "Storage account name '$storageAccount' is taken by someone else. Pick a different suffix." }
    Write-Host "storage account $storageAccount already exists" -ForegroundColor Green
}

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
        Write-Host "  waiting for storage permissions to propagate..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }
}
if (-not $created) { throw "Could not create the '$container' container. Wait a minute and rerun." }
Write-Host "container $container" -ForegroundColor Green

# --- network, in an address range that overlaps nothing we manage ------------
az network vnet create `
    --name $vnet `
    --resource-group $resourceGroup `
    --location $Location `
    --address-prefixes 172.16.0.0/16 `
    --subnet-name $subnet `
    --subnet-prefixes 172.16.10.0/24 `
    --tags Owner=dave.reporting `
    --output none
Write-Host "virtual network $vnet with subnet $subnet" -ForegroundColor Green

# --- the resource IDs students will need for their import blocks -------------
Write-Host ""
Write-Host "Done. These are the resource IDs you will import in Lab 9:" -ForegroundColor Cyan
Write-Host ""

$ids = @(
    @{ Label = 'resource group  '; Id = (az group show --name $resourceGroup --query id -o tsv) }
    @{ Label = 'storage account '; Id = (az storage account show --name $storageAccount --resource-group $resourceGroup --query id -o tsv) }
    @{ Label = 'virtual network '; Id = (az network vnet show --name $vnet --resource-group $resourceGroup --query id -o tsv) }
    @{ Label = 'subnet          '; Id = (az network vnet subnet show --name $subnet --vnet-name $vnet --resource-group $resourceGroup --query id -o tsv) }
)

foreach ($item in $ids) {
    Write-Host "  $($item.Label) $($item.Id)"
}

$containerId = "$($ids[1].Id)/blobServices/default/containers/$container"
Write-Host "  container        $containerId"
Write-Host ""
Write-Host "You can re-list these any time with:" -ForegroundColor Yellow
Write-Host "  az resource list --resource-group $resourceGroup --query `"[].{name:name, type:type, id:id}`" -o table"
