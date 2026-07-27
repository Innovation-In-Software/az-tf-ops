<#
.SYNOPSIS
  Creates the Orders Key Vaults and seeds the VM admin password secret. Lab 8.

.DESCRIPTION
  Like the state backend, the vault is bootstrap infrastructure: the security
  team creates it, and solution teams read from it. Terraform never manages the
  vault that holds the credentials Terraform needs.

  Creates, in resource group rg-summit-security:
    - kv-summit-dev-<suffix>   with secret  vm-admin-password
    - kv-summit-prod-<suffix>  with secret  vm-admin-password

  Both vaults use Azure RBAC rather than legacy access policies, and this script
  grants you Key Vault Secrets Officer so you can read and write secrets.

  Safe to run twice.

.PARAMETER Suffix
  Your 2 to 6 character student suffix. Key Vault names are globally unique.

.PARAMETER Location
  Azure region. Defaults to eastus.

.EXAMPLE
  .\scripts\seed-key-vault.ps1 -Suffix jr42
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,6}$')]
    [string]$Suffix,

    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'

$resourceGroup = 'rg-summit-security'
$secretName    = 'vm-admin-password'

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) { throw "Not signed in. Run 'az login' first." }

$subscriptionId = $account.id
$callerObjectId = az ad signed-in-user show --query id -o tsv

Write-Host "Seeding Key Vaults" -ForegroundColor Cyan
Write-Host "  subscription: $($account.name)"
Write-Host "  you:          $callerObjectId"
Write-Host ""

# The vaults live in their own resource group, not inside an environment. If
# they lived in rg-summit-orders-dev, a `terraform destroy` of dev would take
# the vault with it.
az group create `
    --name $resourceGroup `
    --location $Location `
    --tags solution=orders owner=security-team managed_by=bootstrap `
    --output none
Write-Host "resource group $resourceGroup ready" -ForegroundColor Green

function New-SummitVault {
    param([string]$Environment)

    $vaultName = "kv-summit-$Environment-$Suffix"
    Write-Host ""
    Write-Host "--- $vaultName ---" -ForegroundColor Cyan

    $existing = az keyvault show --name $vaultName --resource-group $resourceGroup --output json 2>$null
    if (-not $existing) {
        # Soft delete is always on for Key Vault. If a vault with this name was
        # deleted recently, creation fails until it is purged.
        $deleted = az keyvault list-deleted --query "[?name=='$vaultName'].name" -o tsv 2>$null
        if ($deleted) {
            Write-Host "  a soft-deleted vault with this name exists, purging it" -ForegroundColor Yellow
            az keyvault purge --name $vaultName --location $Location --output none
            Start-Sleep -Seconds 15
        }

        az keyvault create `
            --name $vaultName `
            --resource-group $resourceGroup `
            --location $Location `
            --enable-rbac-authorization true `
            --retention-days 7 `
            --tags environment=$Environment solution=orders owner=security-team managed_by=bootstrap `
            --output none
        Write-Host "  vault created" -ForegroundColor Green
    }
    else {
        Write-Host "  vault already exists, reusing it" -ForegroundColor Green
    }

    # RBAC-enabled vaults need a data-plane role. Owner on the subscription is
    # a control-plane role and does NOT let you read secrets.
    $scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.KeyVault/vaults/$vaultName"
    az role assignment create `
        --assignee-object-id $callerObjectId `
        --assignee-principal-type User `
        --role "Key Vault Secrets Officer" `
        --scope $scope `
        --output none 2>$null
    Write-Host "  granted you Key Vault Secrets Officer" -ForegroundColor Green

    # Generate a password that satisfies Azure VM complexity rules:
    # 12-72 characters, three of lower / upper / digit / symbol.
    $bytes = New-Object 'System.Byte[]' 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $password = 'Su!' + ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', 'x')

    # Role assignments take up to a couple of minutes to reach the data plane.
    $set = $false
    foreach ($attempt in 1..10) {
        try {
            az keyvault secret set `
                --vault-name $vaultName `
                --name $secretName `
                --value $password `
                --output none 2>$null
            $set = $true
            break
        }
        catch {
            Write-Host "  waiting for the role assignment to propagate (attempt $attempt of 10)..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 15
        }
    }
    if (-not $set) {
        throw "Could not write the secret to $vaultName. Role assignments sometimes take several minutes; wait and rerun this script."
    }
    Write-Host "  secret '$secretName' set" -ForegroundColor Green

    return $vaultName
}

$devVault  = New-SummitVault -Environment 'dev'
$prodVault = New-SummitVault -Environment 'prod'

Write-Host ""
Write-Host "Done. Add these to your tfvars files:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  environments/dev/dev.tfvars"
Write-Host "    key_vault_name                = `"$devVault`""
Write-Host "    key_vault_resource_group_name = `"$resourceGroup`""
Write-Host ""
Write-Host "  environments/prod/prod.tfvars"
Write-Host "    key_vault_name                = `"$prodVault`""
Write-Host "    key_vault_resource_group_name = `"$resourceGroup`""
Write-Host ""
Write-Host "The password is only in the vault. Nobody typed it and nobody knows it." -ForegroundColor Yellow
Write-Host "To read it back:" -ForegroundColor Yellow
Write-Host "  az keyvault secret show --vault-name $devVault --name $secretName --query value -o tsv"
