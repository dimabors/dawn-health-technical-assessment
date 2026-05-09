<#
.SYNOPSIS
  One-time bootstrap of GitHub Actions OIDC -> Azure trust for this repo.

.DESCRIPTION
  Creates (idempotently):
    1. A deployer UAMI ('id-team-alpha-gha-deployer') in the shared RG.
    2. A federated credential trusting GitHub Actions runs from the
       configured repo on the configured branch.
    3. (Optional) Federated credentials for the GitHub environments
       'dev', 'staging', 'prod' so environment-scoped jobs can auth.
    4. Two role assignments scoped to the resource group:
         - Contributor                 (deploy/manage Azure resources)
         - User Access Administrator   (the WI bicep creates roleAssignments,
                                        which requires this permission)

  Re-running is safe: every step is a check-then-create.

  After the script finishes it PRINTS the three values to add to GitHub:
    AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
  Add them as GitHub repository VARIABLES (not secrets) under
    Settings -> Secrets and variables -> Actions -> Variables tab.

.PARAMETER Repo
  GitHub 'owner/repo', e.g. 'dimabors/dawn-health-technical-assessment'.

.PARAMETER Branch
  Branch the workflow is allowed to run from, e.g. 'context/devops-dev'.

.PARAMETER ResourceGroup
  Resource group that the deployer is scoped to (must already exist).

.PARAMETER Location
  Azure region for the UAMI.

.PARAMETER DeployerName
  UAMI name. Default 'id-team-alpha-gha-deployer'.

.PARAMETER GitHubEnvironments
  GitHub Environment names to also create federated creds for. These let
  jobs that target `environment: dev|staging|prod` authenticate even if
  they run from a different branch (e.g. a release branch).
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Repo,
  [string]$Branch              = 'context/devops-dev',
  [string]$ResourceGroup       = 'rg-team-alpha',
  [string]$Location            = 'northeurope',
  [string]$DeployerName        = 'id-team-alpha-gha-deployer',
  [string[]]$GitHubEnvironments = @('dev','staging','prod')
)

$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "    $m" -ForegroundColor Green }
function Warn2($m){ Write-Host "    $m" -ForegroundColor Yellow }
function Die($m) { Write-Host "    $m" -ForegroundColor Red; exit 1 }

# Make sure az is on PATH in this session.
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Die "az CLI not on PATH. Install: winget install -e --id Microsoft.AzureCLI"
}

$sub = az account show -o json | ConvertFrom-Json
if (-not $sub) { Die "Not logged in. Run: az login" }
Step "Subscription: $($sub.name) ($($sub.id))"
$subId    = $sub.id
$tenantId = $sub.tenantId

# 1. Resource group must exist (we won't create it here — it's the shared RG).
if ((az group exists -n $ResourceGroup) -ne 'true') {
  Die "Resource group '$ResourceGroup' not found. Run Deploy-Infrastructure.ps1 first."
}

# 2. Deployer UAMI
Step "Deployer UAMI '$DeployerName'"
$uamiExists = (az identity list -g $ResourceGroup --query "[?name=='$DeployerName'].name" -o tsv)
if (-not $uamiExists) {
  az identity create -n $DeployerName -g $ResourceGroup -l $Location | Out-Null
  Ok "Created"
} else { Ok "Exists" }

$uami = az identity show -n $DeployerName -g $ResourceGroup -o json | ConvertFrom-Json
$clientId    = $uami.clientId
$principalId = $uami.principalId
Ok "clientId=$clientId"

# 3. Federated credentials
function Ensure-FedCred {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Subject
  )
  $existing = (az identity federated-credential list `
                  --identity-name $DeployerName -g $ResourceGroup `
                  --query "[?name=='$Name'].name" -o tsv)
  if ($existing) {
    Ok "fed-cred '$Name' exists"
    return
  }
  $body = @{
    name      = $Name
    issuer    = 'https://token.actions.githubusercontent.com'
    subject   = $Subject
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json -Compress
  $tmp = New-TemporaryFile
  $body | Out-File -FilePath $tmp -Encoding ascii
  az identity federated-credential create `
    --identity-name $DeployerName -g $ResourceGroup `
    --name $Name `
    --issuer 'https://token.actions.githubusercontent.com' `
    --subject $Subject `
    --audiences 'api://AzureADTokenExchange' | Out-Null
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  Ok "fed-cred '$Name' created (subject=$Subject)"
}

Step "Federated credential for branch '$Branch'"
# Branch trust: any workflow run from refs/heads/<branch> on this repo.
$branchSubject = "repo:${Repo}:ref:refs/heads/${Branch}"
$branchSlug    = ($Branch -replace '[^a-zA-Z0-9]', '-')
Ensure-FedCred -Name "gh-branch-$branchSlug" -Subject $branchSubject

Step "Federated credentials for GitHub Environments"
foreach ($envName in $GitHubEnvironments) {
  # Environment trust: workflow jobs that target `environment: <name>`.
  $envSubject = "repo:${Repo}:environment:${envName}"
  Ensure-FedCred -Name "gh-env-$envName" -Subject $envSubject
}

# Pull-request trust (optional but useful for plan-only runs)
Step "Federated credential for pull requests"
Ensure-FedCred -Name 'gh-pull-request' -Subject "repo:${Repo}:pull_request"

# 4. Role assignments at RG scope
Step "Role assignments on /resourceGroups/$ResourceGroup"
$rgScope = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
foreach ($role in @('Contributor','User Access Administrator')) {
  $hit = (az role assignment list --assignee $principalId --scope $rgScope `
            --query "[?roleDefinitionName=='$role'].roleDefinitionName" -o tsv)
  if (-not $hit) {
    az role assignment create --assignee-object-id $principalId `
      --assignee-principal-type ServicePrincipal `
      --role "$role" --scope $rgScope | Out-Null
    Ok "Granted '$role'"
  } else { Ok "Already has '$role'" }
}

# 5. Print the three values to put into GitHub.
Write-Host ""
Step "Add these as GitHub repo Variables (Settings -> Secrets and variables -> Actions -> Variables)"
Write-Host ""
Write-Host "  AZURE_CLIENT_ID       = $clientId"        -ForegroundColor Yellow
Write-Host "  AZURE_TENANT_ID       = $tenantId"        -ForegroundColor Yellow
Write-Host "  AZURE_SUBSCRIPTION_ID = $subId"           -ForegroundColor Yellow
Write-Host ""
Step "Done."
