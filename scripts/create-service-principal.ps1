<#
.SYNOPSIS
  Creates the service principal that GitHub Actions uses to run Terraform, and
  prints the GitHub secrets to store. Lab 10.

.DESCRIPTION
  A service principal (SP) is an identity for software rather than a person. The
  pipeline authenticates as this SP instead of as you, which means the pipeline
  keeps working when you are on holiday and its permissions can be scoped
  independently of yours.

  Creates:
    - an app registration and service principal, sp-summit-orders-<name>
    - a Contributor role assignment at subscription scope
    - Key Vault Secrets User on both Orders vaults, so the pipeline can read
      the VM admin password

  Prints the four values to store as GitHub Actions secrets. It does NOT store
  them for you unless you pass -Repo and have the GitHub CLI installed.

  The client secret is displayed exactly once. Azure cannot show it again.

.PARAMETER Name
  A unique-ish name fragment, usually your GitHub username.

.PARAMETER Suffix
  Your 2 to 6 character student suffix, used to find your Key Vaults.

.PARAMETER Repo
  Optional. owner/repo, for example jrivera/az-tf-ops-jrivera. If supplied and
  the GitHub CLI (gh) is signed in, the secrets are set for you.

.EXAMPLE
  .\scripts\create-service-principal.ps1 -Name jrivera -Suffix jr63

.EXAMPLE
  .\scripts\create-service-principal.ps1 -Name jrivera -Suffix jr63 -Repo jrivera/az-tf-ops-jrivera
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,6}$')]
    [string]$Suffix,

    [string]$Repo
)

# az is a native command, not a cmdlet. When it fails it writes to stderr and sets
# a non-zero $LASTEXITCODE; it never throws. Windows PowerShell converts that
# stderr write into a *terminating* error whenever $ErrorActionPreference is
# 'Stop', and `2>$null` does NOT prevent it. That kills this script on failures it
# is supposed to handle, such as probing for a vault that is not there yet, before
# any exit-code check can run. So keep the preference at 'Continue' and test
# $LASTEXITCODE after each az call whose outcome matters.
$ErrorActionPreference = 'Continue'

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) { throw "Not signed in. Run 'az login' first." }

$subscriptionId = $account.id
$tenantId       = $account.tenantId
$spName         = "sp-summit-orders-$Name"

Write-Host "Creating service principal $spName" -ForegroundColor Cyan
Write-Host "  subscription: $($account.name) ($subscriptionId)"
Write-Host ""

# --- the service principal ---------------------------------------------------
# Contributor at subscription scope is broader than a real production pipeline
# should get. It is used here so one credential covers every lab. In production,
# scope the assignment to the resource groups the pipeline actually manages.
$existing = az ad sp list --display-name $spName --query "[0].appId" -o tsv 2>$null
if ($existing) {
    Write-Host "A service principal named $spName already exists (appId $existing)." -ForegroundColor Yellow
    Write-Host "Azure cannot show you its existing secret. Creating a new secret for it." -ForegroundColor Yellow
    $appId  = $existing
    $secret = az ad app credential reset --id $appId --append --query password -o tsv
}
else {
    $sp = az ad sp create-for-rbac `
        --name $spName `
        --role Contributor `
        --scopes "/subscriptions/$subscriptionId" `
        --output json | ConvertFrom-Json

    $appId  = $sp.appId
    $secret = $sp.password
    Write-Host "service principal created" -ForegroundColor Green
    Start-Sleep -Seconds 10   # give Entra ID a moment before role assignments
}

$spObjectId = az ad sp show --id $appId --query id -o tsv

# --- Key Vault access ---------------------------------------------------------
# This is the bootstrapping step from Lab 8: the pipeline cannot read the vault
# until somebody outside the pipeline grants it access.
foreach ($environment in @('dev', 'prod')) {
    $vaultName = "kv-summit-$environment-$Suffix"
    $vaultId = az keyvault show --name $vaultName --resource-group rg-summit-security --query id -o tsv 2>$null

    if (-not $vaultId) {
        Write-Host "  vault $vaultName not found, skipping. Run seed-key-vault.ps1 first." -ForegroundColor Yellow
        continue
    }

    az role assignment create `
        --assignee-object-id $spObjectId `
        --assignee-principal-type ServicePrincipal `
        --role "Key Vault Secrets User" `
        --scope $vaultId `
        --output none 2>$null

    Write-Host "  granted Key Vault Secrets User on $vaultName" -ForegroundColor Green
}

# --- output -------------------------------------------------------------------
Write-Host ""
Write-Host "==================== STORE THESE AS GITHUB SECRETS ====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  AZURE_CLIENT_ID        $appId"
Write-Host "  AZURE_CLIENT_SECRET    $secret"
Write-Host "  AZURE_TENANT_ID        $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID  $subscriptionId"
Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The client secret is shown once. Azure stores a hash, not the value." -ForegroundColor Yellow
Write-Host "If you lose it, rerun this script to generate a new one." -ForegroundColor Yellow
Write-Host ""
Write-Host "Set them at: https://github.com/<owner>/<repo>/settings/secrets/actions" -ForegroundColor Yellow

# --- optionally push them to GitHub ------------------------------------------
if ($Repo) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Host ""
        Write-Host "GitHub CLI (gh) not found. Add the secrets through the web UI." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Setting secrets on $Repo via the GitHub CLI..." -ForegroundColor Cyan
    $appId          | gh secret set AZURE_CLIENT_ID       --repo $Repo
    $secret         | gh secret set AZURE_CLIENT_SECRET   --repo $Repo
    $tenantId       | gh secret set AZURE_TENANT_ID       --repo $Repo
    $subscriptionId | gh secret set AZURE_SUBSCRIPTION_ID --repo $Repo
    Write-Host "done. Confirm with: gh secret list --repo $Repo" -ForegroundColor Green
    Write-Host ""
    Write-Host "You still need TF_VAR_ALLOWED_SSH_SOURCE. Set it with:" -ForegroundColor Yellow
    Write-Host "  `"`$(Invoke-RestMethod https://api.ipify.org)/32`" | gh secret set TF_VAR_ALLOWED_SSH_SOURCE --repo $Repo"
}
