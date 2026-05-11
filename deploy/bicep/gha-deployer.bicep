// GitHub Actions deployer — UAMI + federated credentials + RG role assignments.
//
// Trust subjects map 1:1 to what the workflow asserts in its OIDC token:
//   - branch trust:       repo:<owner/repo>:ref:refs/heads/<branch>
//   - environment trust:  repo:<owner/repo>:environment:<env>     (per dev/staging/prod)
//   - pull request trust: repo:<owner/repo>:pull_request
//
// Roles on the RG:
//   - Contributor                  — manage Azure resources
//   - User Access Administrator    — required because the WI bicep creates
//                                    its own roleAssignments (KV Secrets User)
//
// Run locally ONCE with `az deployment group create` (chicken-and-egg: GitHub
// can't authenticate until this UAMI exists). After that, CI re-applies it
// idempotently on every infra workflow run.

targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('GitHub repo in owner/repo form.')
param repo string

@description('Branch the infra workflow runs from (e.g. context/devops-dev).')
param branch string = 'context/devops-dev'

@description('GitHub Environments to grant trust to.')
param githubEnvironments array = [
  'dev'
  'staging'
  'prod'
]

@description('Trust pull request runs (read-only / what-if).')
param trustPullRequests bool = true

@description('Deployer UAMI name.')
param deployerName string = 'id-team-alpha-gha-deployer'

resource deployer 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deployerName
  location: location
}

var ghIssuer = 'https://token.actions.githubusercontent.com'
var audience = [ 'api://AzureADTokenExchange' ]

// Branch trust
resource fcBranch 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployer
  name: 'gh-branch-${replace(branch, '/', '-')}'
  properties: {
    issuer: ghIssuer
    subject: 'repo:${repo}:ref:refs/heads/${branch}'
    audiences: audience
  }
}

// Per-environment trust (serialized — Azure rejects concurrent FIC writes on a single UAMI)
@batchSize(1)
resource fcEnv 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [for env in githubEnvironments: {
  parent: deployer
  name: 'gh-env-${env}'
  properties: {
    issuer: ghIssuer
    subject: 'repo:${repo}:environment:${env}'
    audiences: audience
  }
  dependsOn: [ fcBranch ]
}]

// Pull request trust
resource fcPr 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (trustPullRequests) {
  parent: deployer
  name: 'gh-pull-request'
  properties: {
    issuer: ghIssuer
    subject: 'repo:${repo}:pull_request'
    audiences: audience
  }
  dependsOn: [ fcEnv ]
}

// Role assignments on the RG
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var uaaRoleId         = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'

resource raContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, deployer.id, contributorRoleId)
  properties: {
    principalId: deployer.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
}

resource raUaa 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, deployer.id, uaaRoleId)
  properties: {
    principalId: deployer.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', uaaRoleId)
  }
}

output deployerClientId string = deployer.properties.clientId
output deployerPrincipalId string = deployer.properties.principalId
output tenantId string = subscription().tenantId
output subscriptionId string = subscription().subscriptionId
