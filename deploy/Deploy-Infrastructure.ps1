<#
.SYNOPSIS
  Bootstraps the shared platform: resource group, ACR, and AKS with OIDC + Workload Identity.
  Idempotent — safe to re-run.

.PARAMETER ResourceGroup
.PARAMETER Location
.PARAMETER AksClusterName
.PARAMETER AcrName
  Must be globally unique, lowercase letters/numbers, 5-50 chars.
.PARAMETER NodeCount
  Defaults to 1 (cheapest viable cluster for an assessment).
.PARAMETER NodeVmSize
  Defaults to Standard_B2s (~£25/mo).

.EXAMPLE
  ./deploy/Deploy-Infrastructure.ps1 `
    -ResourceGroup rg-team-alpha `
    -Location westeurope `
    -AksClusterName aks-shared `
    -AcrName dawnhealthacr$(Get-Random -Maximum 9999)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ResourceGroup,
  [Parameter(Mandatory)] [string]$Location,
  [Parameter(Mandatory)] [string]$AksClusterName,
  [Parameter(Mandatory)] [string]$AcrName,
  [int]$NodeCount = 1,
  [string]$NodeVmSize = 'Standard_B2s_v2'
)

$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "    $m" -ForegroundColor Green }
function Warn2($m){ Write-Host "    $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "    $m" -ForegroundColor Red; exit 1 }
function Assert-Ok($what){
  if ($LASTEXITCODE -ne 0) { Die "$what failed (exit $LASTEXITCODE)" }
}

# Ensure az is on PATH within this session even if PowerShell wasn't restarted post-install.
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "az CLI not on PATH. Install it (winget install -e --id Microsoft.AzureCLI) and reopen PowerShell."
}

# 1. Resource group
Step "Resource group $ResourceGroup ($Location)"
if ((az group exists -n $ResourceGroup) -eq 'false') {
  az group create -n $ResourceGroup -l $Location | Out-Null
  Ok "Created"
} else { Ok "Exists" }

# 1b. Register required resource providers (idempotent; no-op if already registered)
Step "Registering resource providers"
$providers = @(
  'Microsoft.ContainerRegistry',
  'Microsoft.ContainerService',
  'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity',
  'Microsoft.OperationalInsights',
  'Microsoft.OperationsManagement'
)
foreach ($p in $providers) {
  $state = (az provider show -n $p --query registrationState -o tsv)
  if ($state -ne 'Registered') {
    Warn2 "Registering $p (currently: $state)"
    az provider register -n $p | Out-Null
  } else { Ok "$p already registered" }
}
# Wait until the two we'll use immediately are actually registered
foreach ($p in @('Microsoft.ContainerRegistry','Microsoft.ContainerService')) {
  while ((az provider show -n $p --query registrationState -o tsv) -ne 'Registered') {
    Warn2 "Waiting for $p to finish registering..."
    Start-Sleep -Seconds 10
  }
}
Ok "Providers ready"

# 2. ACR (Basic tier — cheapest; AKS can pull from it once attached)
Step "ACR $AcrName"
$acrExists = (az acr list -g $ResourceGroup --query "[?name=='$AcrName'].name" -o tsv)
if (-not $acrExists) {
  Warn2 "Creating ACR (Basic tier)"
  az acr create -n $AcrName -g $ResourceGroup --sku Basic -l $Location | Out-Null
  Ok "Created"
} else { Ok "Exists" }
$acrLoginServer = (az acr show -n $AcrName -g $ResourceGroup --query loginServer -o tsv)

# 3. AKS — small cluster, system-assigned MI, OIDC + workload identity enabled at create
Step "AKS $AksClusterName"
$aksExists = (az aks list -g $ResourceGroup --query "[?name=='$AksClusterName'].name" -o tsv)
if (-not $aksExists) {
  Warn2 "Creating AKS cluster (this takes ~5-10 minutes)..."
  az aks create `
    -n $AksClusterName `
    -g $ResourceGroup `
    -l $Location `
    --node-count $NodeCount `
    --node-vm-size $NodeVmSize `
    --enable-oidc-issuer `
    --enable-workload-identity `
    --enable-managed-identity `
    --attach-acr $AcrName `
    --generate-ssh-keys `
    --network-plugin azure `
    --tier free | Out-Null
  Ok "Created"
} else {
  $aks = az aks show -n $AksClusterName -g $ResourceGroup -o json | ConvertFrom-Json
  $needsUpdate = (-not $aks.oidcIssuerProfile.enabled) -or (-not $aks.securityProfile.workloadIdentity.enabled)
  if ($needsUpdate) {
    Warn2 "Enabling OIDC + workload identity on existing cluster"
    az aks update -n $AksClusterName -g $ResourceGroup --enable-oidc-issuer --enable-workload-identity | Out-Null
  }
  Ok "Exists"
  # Make sure ACR is attached
  Step "Attaching ACR $AcrName to AKS"
  az aks update -n $AksClusterName -g $ResourceGroup --attach-acr $AcrName | Out-Null
  Ok "Attached"
}

# 4. kubeconfig
Step "Fetching kubeconfig"
az aks get-credentials -g $ResourceGroup -n $AksClusterName --overwrite-existing | Out-Null
Ok "kubectl context: $(kubectl config current-context 2>$null)"

# 5. Summary
$issuer = az aks show -n $AksClusterName -g $ResourceGroup --query oidcIssuerProfile.issuerURL -o tsv
Write-Host ""
Step "Bootstrap complete"
[pscustomobject]@{
  ResourceGroup = $ResourceGroup
  Location      = $Location
  AKS           = $AksClusterName
  ACR           = $AcrName
  AcrLogin      = $acrLoginServer
  OidcIssuer    = $issuer
} | Format-List
