// Part 1.2 — Workload Identity for team-alpha (parameterised per environment)
//
// Provisions, for ONE environment (dev / staging / prod):
//   1. A User-Assigned Managed Identity (UAMI) — the AAD identity the pod assumes.
//   2. A federated credential trusting the K8s ServiceAccount
//      `team-alpha-workload-sa` in namespace `team-alpha-<env>` on the AKS
//      cluster. No client secret is ever stored.
//   3. A "Key Vault Secrets User" role assignment scoped to the env-specific
//      Key Vault, so the workload can READ secrets but not manage them.
//
// REQUIRED ServiceAccount annotation (apply in each env's namespace):
//
//   metadata:
//     annotations:
//       azure.workload.identity/client-id: <uamiClientId output of this deploy>
//     # The Pod template must also carry:  azure.workload.identity/use: "true"
//
// The annotation tells the Azure Workload Identity webhook which UAMI to bind
// the projected SA token to. Without it the webhook won't inject AZURE_CLIENT_ID
// or the token volume, and AAD token exchange fails. The federated credential's
// subject (`system:serviceaccount:<ns>:<sa>`) must match on both sides exactly.

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Environment suffix: dev | staging | prod.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Name of the existing AKS cluster (used to read its OIDC issuer URL).')
param aksClusterName string

@description('Resource group of the AKS cluster (defaults to current RG).')
param aksResourceGroup string = resourceGroup().name

@description('Override the Key Vault name. Defaults to kv-team-alpha-<env>.')
param keyVaultName string = 'kv-team-alpha-${environment}'

@description('Override the K8s namespace. Defaults to team-alpha-<env>.')
param namespaceName string = 'team-alpha-${environment}'

@description('K8s ServiceAccount name the workload runs as.')
param serviceAccountName string = 'team-alpha-workload-sa'

// Existing AKS cluster — workload identity requires --enable-oidc-issuer
// and --enable-workload-identity to have been set on the cluster.
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksClusterName
  scope: resourceGroup(aksResourceGroup)
}

// 1. UAMI — one per environment so we can scope KV access independently.
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-team-alpha-workload-${environment}'
  location: location
}

// 2. Federated credential. Subject MUST match `system:serviceaccount:<ns>:<sa>`.
//    Audience MUST be `api://AzureADTokenExchange`.
resource fedCred 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: 'fc-team-alpha-backend-${environment}'
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${namespaceName}:${serviceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// 3. Key Vault Secrets User on the env-scoped vault — read-only at the data plane.
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Built-in role definition ID for "Key Vault Secrets User".
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  // GUID derived from scope+principal+role makes the deployment idempotent.
  name: guid(kv.id, uami.id, kvSecretsUserRoleId)
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      kvSecretsUserRoleId
    )
  }
}

output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
output uamiResourceId string = uami.id
output aksOidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
output keyVaultId string = kv.id
output namespaceName string = namespaceName
