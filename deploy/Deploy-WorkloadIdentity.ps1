<#
.SYNOPSIS
  Idempotent end-to-end deployer for Part 1.2 — Workload Identity per environment.

.DESCRIPTION
  For each environment (dev / staging / prod) this script:
    1. Ensures the resource group exists.
    2. Ensures the AKS cluster has OIDC issuer + workload identity enabled.
    3. Ensures the env-scoped Key Vault exists (RBAC mode).
    4. Ensures the K8s namespace exists (when kubectl is configured).
    5. Deploys part1/workload-identity.bicep and captures the UAMI clientId.
    6. Annotates the K8s ServiceAccount with the clientId.
    7. Writes outputs to deploy/outputs/<env>.json so the Pod template can
       reference it later.

  Re-running the script is safe: every step is a check-then-create, and the
  bicep itself uses guid()-derived names for the role assignment.

.PARAMETER Environments
  Subset of dev / staging / prod to deploy. Defaults to all three.

.PARAMETER ResourceGroup
  Resource group that hosts the AKS cluster, KVs, and UAMIs.

.PARAMETER AksClusterName
.PARAMETER Location
.PARAMETER SkipKubernetes
  If set, only deploys Azure resources; doesn't touch the cluster.

.EXAMPLE
  ./deploy/Deploy-WorkloadIdentity.ps1 -ResourceGroup rg-team-alpha -AksClusterName aks-shared

.EXAMPLE
  ./deploy/Deploy-WorkloadIdentity.ps1 -Environments dev -ResourceGroup rg-team-alpha -AksClusterName aks-shared
#>

[CmdletBinding()]
param(
  [ValidateSet('dev', 'staging', 'prod')]
  [string[]]$Environments = @('dev', 'staging', 'prod'),

  [Parameter(Mandatory)]
  [string]$ResourceGroup,

  [Parameter(Mandatory)]
  [string]$AksClusterName,

  [string]$Location = 'westeurope',

  [string]$BicepFile = 'part1/workload-identity.bicep',

  [switch]$SkipKubernetes
)

$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok  ([string]$msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
# Refresh PATH from registry so a freshly-installed az/kubectl is visible
# even if PowerShell wasn't restarted after install.
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

Write-Step "Verifying tooling"
foreach ($cmd in @('az', 'kubectl')) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    if ($cmd -eq 'kubectl' -and $SkipKubernetes) { continue }
    throw "Required command '$cmd' not on PATH."
  }
}
$account = az account show -o json | ConvertFrom-Json
Write-Ok "Subscription: $($account.name) ($($account.id))"

# ---------------------------------------------------------------------------
# 1. Resource group
# ---------------------------------------------------------------------------
Write-Step "Ensuring resource group '$ResourceGroup' in $Location"
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq 'false') {
  az group create --name $ResourceGroup --location $Location | Out-Null
  Write-Ok "Created"
} else {
  Write-Ok "Exists"
}

# ---------------------------------------------------------------------------
# 2. AKS — enable OIDC issuer + workload identity if not already on
# ---------------------------------------------------------------------------
Write-Step "Verifying AKS cluster '$AksClusterName' has OIDC + workload identity"
$aks = az aks show -g $ResourceGroup -n $AksClusterName -o json | ConvertFrom-Json
if (-not $aks) {
  throw "AKS cluster '$AksClusterName' not found in resource group '$ResourceGroup'. Run Deploy-Infrastructure.ps1 first."
}
$oidcOn = $aks.oidcIssuerProfile.enabled
$wiOn   = $aks.securityProfile.workloadIdentity.enabled
if (-not $oidcOn -or -not $wiOn) {
  Write-Warn2 "Enabling OIDC issuer + workload identity (this can take ~5-10 min)"
  az aks update -g $ResourceGroup -n $AksClusterName `
    --enable-oidc-issuer --enable-workload-identity | Out-Null
  $aks = az aks show -g $ResourceGroup -n $AksClusterName -o json | ConvertFrom-Json
}
Write-Ok "OIDC issuer: $($aks.oidcIssuerProfile.issuerURL)"

# ---------------------------------------------------------------------------
# 3. kubeconfig (unless skipped)
# ---------------------------------------------------------------------------
if (-not $SkipKubernetes) {
  Write-Step "Fetching kubeconfig"
  az aks get-credentials -g $ResourceGroup -n $AksClusterName --overwrite-existing | Out-Null
  Write-Ok "kubectl context: $(kubectl config current-context)"
}

# ---------------------------------------------------------------------------
# 4. Per-environment deploy loop
# ---------------------------------------------------------------------------
$outDir = Join-Path $PSScriptRoot 'outputs'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$results = @()

foreach ($env in $Environments) {
  Write-Host ""
  Write-Step "=== Environment: $env ==="

  $kvName    = "kv-team-alpha-$env"
  $namespace = "team-alpha-$env"
  $saName    = "team-alpha-workload-sa"

  # 4a. Ensure the env-scoped Key Vault (RBAC-mode, soft-delete on by default)
  $kvExists = (az keyvault list -g $ResourceGroup --query "[?name=='$kvName'].name" -o tsv)
  if (-not $kvExists) {
    Write-Warn2 "Creating Key Vault $kvName"
    az keyvault create `
      --name $kvName `
      --resource-group $ResourceGroup `
      --location $Location `
      --enable-rbac-authorization true `
      --retention-days 7 | Out-Null
    Write-Ok "Created $kvName"
  } else {
    Write-Ok "Key Vault $kvName exists"
  }

  # 4b. Ensure the K8s namespace
  if (-not $SkipKubernetes) {
    $nsExists = kubectl get ns $namespace --ignore-not-found -o name 2>$null
    if (-not $nsExists) {
      kubectl create namespace $namespace | Out-Null
      Write-Ok "Created namespace $namespace"
    } else {
      Write-Ok "Namespace $namespace exists"
    }
  }

  # 4c. Deploy bicep
  Write-Step "Deploying bicep for $env"
  $deployName = "wi-$env-$(Get-Date -Format 'yyyyMMddHHmmss')"
  $deployJson = az deployment group create `
    --resource-group $ResourceGroup `
    --name $deployName `
    --template-file $BicepFile `
    --parameters environment=$env `
                 aksClusterName=$AksClusterName `
                 aksResourceGroup=$ResourceGroup `
    -o json | ConvertFrom-Json

  if ($LASTEXITCODE -ne 0 -or -not $deployJson) {
    throw "Deployment failed for environment '$env'. Run with -Verbose or check 'az deployment group show -g $ResourceGroup -n $deployName'."
  }

  $clientId = $deployJson.properties.outputs.uamiClientId.value
  Write-Ok "UAMI clientId = $clientId"

  # 4d. Save outputs to JSON for Part 2 / 3 to consume
  $outFile = Join-Path $outDir "$env.json"
  $deployJson.properties.outputs | ConvertTo-Json -Depth 6 | Out-File $outFile -Encoding utf8
  Write-Ok "Outputs -> $outFile"

  # 4e. Apply the ServiceAccount with the workload-identity annotation
  if (-not $SkipKubernetes) {
    $saYaml = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $saName
  namespace: $namespace
  annotations:
    azure.workload.identity/client-id: "$clientId"
  labels:
    azure.workload.identity/use: "true"
"@
    $saYaml | kubectl apply -f - | Out-Null
    Write-Ok "ServiceAccount $namespace/$saName annotated"
  }

  $results += [pscustomobject]@{
    Environment = $env
    Namespace   = $namespace
    KeyVault    = $kvName
    ClientId    = $clientId
    Deployment  = $deployName
  }
}

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Step "Summary"
$results | Format-Table -AutoSize
Write-Host ""
Write-Ok "Per-env JSON outputs are under: $outDir"
Write-Ok "Done."
