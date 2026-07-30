<#
.SYNOPSIS
  Tears down everything the class created. Lab 12.

.DESCRIPTION
  Destroys in dependency order, using Terraform where Terraform built it and the
  Azure CLI for the bootstrap resources Terraform never managed.

  Order matters:
    1. environments/dev              terraform destroy
    2. environments/prod             terraform destroy
    3. environments/legacy-reporting terraform destroy
    4. rg-summit-security            az, plus a Key Vault purge
    5. rg-summit-tfstate             az, LAST, because steps 1-3 read state from it
    6. the service principal         az

  Nothing is deleted without asking. Run with -WhatIf to see the plan only.

.PARAMETER Suffix
  Your student suffix, used to find the vaults and the state account.

.PARAMETER SkipBackend
  Leave rg-summit-tfstate in place. Use this if you want to keep the state
  history for reference.

.PARAMETER SkipServicePrincipal
  Leave the Lab 10 service principal in place.

.EXAMPLE
  .\scripts\destroy-all.ps1 -Suffix jr63 -WhatIf

.EXAMPLE
  .\scripts\destroy-all.ps1 -Suffix jr63
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{2,6}$')]
    [string]$Suffix,

    [switch]$SkipBackend,
    [switch]$SkipServicePrincipal
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

$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "This will DESTROY the following in $($account.name):" -ForegroundColor Red
Write-Host "  rg-summit-orders-dev"
Write-Host "  rg-summit-orders-prod"
Write-Host "  rg-legacy-reporting"
Write-Host "  rg-summit-security   (including both Key Vaults, purged)"
if (-not $SkipBackend)          { Write-Host "  rg-summit-tfstate    (including all Terraform state)" }
if (-not $SkipServicePrincipal) { Write-Host "  the sp-summit-orders-* service principal" }
Write-Host ""

if (-not $PSCmdlet.ShouldProcess("the Summit lab environment", "Destroy everything")) {
    Write-Host "Nothing was deleted." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------------------
# 1-3. Terraform-managed environments.
# ---------------------------------------------------------------------------
$environments = @(
    @{ Dir = 'dev';               VarFile = 'dev.tfvars' }
    @{ Dir = 'prod';              VarFile = 'prod.tfvars' }
    @{ Dir = 'legacy-reporting';  VarFile = $null }
)

# The VM password comes from Key Vault, and destroy still evaluates the data
# source, so the vaults have to survive until the environments are gone.
foreach ($environment in $environments) {
    $path = Join-Path $repoRoot "environments/$($environment.Dir)"
    if (-not (Test-Path $path)) {
        Write-Host "skipping $($environment.Dir): $path not found" -ForegroundColor DarkGray
        continue
    }

    Write-Host ""
    Write-Host "=== terraform destroy: $($environment.Dir) ===" -ForegroundColor Cyan

    Push-Location $path
    try {
        terraform init -input=false | Out-Null

        $arguments = @('destroy', '-auto-approve', '-input=false')
        if ($environment.VarFile -and (Test-Path $environment.VarFile)) {
            $arguments += "-var-file=$($environment.VarFile)"
        }

        & terraform @arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host "destroy failed for $($environment.Dir). Fix it and rerun, or delete the resource group by hand." -ForegroundColor Red
        }
        else {
            Write-Host "$($environment.Dir) destroyed" -ForegroundColor Green
        }
    }
    finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 4. Key Vaults. Soft delete means "deleted" vaults still hold their names,
#    so purge them or the name is unavailable for 7 days.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== rg-summit-security ===" -ForegroundColor Cyan

foreach ($environment in @('dev', 'prod')) {
    $vaultName = "kv-summit-$environment-$Suffix"
    az keyvault delete --name $vaultName --resource-group rg-summit-security --output none 2>$null
    az keyvault purge --name $vaultName --location eastus --output none 2>$null
    Write-Host "  $vaultName deleted and purged" -ForegroundColor Green
}

az group delete --name rg-summit-security --yes --no-wait --output none 2>$null
Write-Host "  resource group deletion started" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 5. The state backend. LAST: the destroys above needed it.
# ---------------------------------------------------------------------------
if (-not $SkipBackend) {
    Write-Host ""
    Write-Host "=== rg-summit-tfstate ===" -ForegroundColor Cyan
    az group delete --name rg-summit-tfstate --yes --no-wait --output none 2>$null
    Write-Host "  resource group deletion started" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "keeping rg-summit-tfstate" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 6. The service principal.
# ---------------------------------------------------------------------------
if (-not $SkipServicePrincipal) {
    Write-Host ""
    Write-Host "=== service principal ===" -ForegroundColor Cyan
    $appIds = az ad sp list --filter "startswith(displayName,'sp-summit-orders-')" --query "[].appId" -o tsv 2>$null
    foreach ($appId in $appIds) {
        if ($appId) {
            az ad app delete --id $appId --output none 2>$null
            Write-Host "  deleted app registration $appId" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Teardown started. Resource group deletion runs in the background." -ForegroundColor Cyan
Write-Host "Check in a few minutes with:" -ForegroundColor Yellow
Write-Host "  az group list --query `"[].name`" -o table"
Write-Host ""
Write-Host "Anything still listed after ten minutes should be deleted in the portal." -ForegroundColor Yellow
