// Part 1.2 — Workload Identity for team-alpha (dev environment)
//
// Provisions the Azure-side of the Workload Identity binding so that
// team-alpha pods can authenticate to Key Vault without stored credentials.
//
// Three resources are required:
//   1. User-Assigned Managed Identity (UAMI)   — the Azure identity the pod will assume
//   2. Federated Credential                    — binds the UAMI to the K8s ServiceAccount
//   3. Key Vault role assignment               — grants the UAMI read access to KV secrets
//
// Companion Kubernetes resource: part1/namespace.yaml (ServiceAccount + annotation below).
//
// REQUIRED ServiceAccount ANNOTATION
// ===================================
// For the Workload Identity webhook to exchange the projected OIDC token for an
// Azure access token, the ServiceAccount MUST carry:
//
//   azure.workload.identity/client-id: <uamiClientId output below>
//
// Without this annotation the mutating webhook does not inject the
// AZURE_CLIENT_ID env var and the OIDC token mount — the pod starts but
// every Azure SDK call fails with an authentication error.
// Optionally also annotate with:
//   azure.workload.identity/tenant-id: <tenantId>   # defaults to cluster tenant if omitted
//
// The pod itself must also carry the label:
//   azure.workload.identity/use: "true"

targetScope = 'resourceGroup'

@description('Azure region — defaults to the resource group region.')
param location string = resourceGroup().location

//make sure we get the OIDC issuer URL from the existing AKS cluster instead of hardcoding it. Only Trust AKS clusters.
@description('OIDC issuer URL of the shared AKS cluster. Retrieve with: az aks show -n <cluster> -g <rg> --query oidcIssuerProfile.issuerURL -o tsv')
param oidcIssuerUrl string

@description('Name of the existing Key Vault the team needs to read secrets from.')
param keyVaultName string = 'kv-team-alpha-dev'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Kubernetes coordinates taht starts from part1/namespace.yaml
var k8sNamespace      = 'team-alpha'
var k8sServiceAccount = 'team-alpha-workload-sa'

// Built-in role: Key Vault Secrets User (read secret values, no management plane access)
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ---------------------------------------------------------------------------
// 1. User-Assigned Managed Identity
// ---------------------------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-team-alpha-workload-dev'
  location: location
}

// ---------------------------------------------------------------------------
// 2. Federated Identity Credential
//
// Tells Azure AD to trust a token that claims:
//   iss = oidcIssuerUrl          (this AKS cluster)
//   sub = system:serviceaccount:<namespace>:<serviceAccount>
//
// Any other token is rejected — no other namespace or SA can impersonate this identity.
// ---------------------------------------------------------------------------

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: 'fc-team-alpha-backend-dev'
  properties: {
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccount}'
    // 'api://AzureADTokenExchange' is the fixed audience the AKS OIDC webhook uses.
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// ---------------------------------------------------------------------------
// 3. Key Vault role assignment — Key Vault Secrets User on kv-team-alpha-dev
//
// Scoped to the specific vault (not the whole resource group) to follow
// least-privilege: the UAMI can read secrets only from this vault.
// ---------------------------------------------------------------------------

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Deterministic GUID — safe to re-run (idempotent).
  name: guid(kv.id, uami.id, kvSecretsUserRoleId)
  scope: kv
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      kvSecretsUserRoleId
    )
  }
}

// ---------------------------------------------------------------------------
// Outputs — feed these into the ServiceAccount annotation and pod identity spec
// ---------------------------------------------------------------------------

@description('Client ID to paste into the azure.workload.identity/client-id annotation on the ServiceAccount.')
output uamiClientId string = uami.properties.clientId

@description('Full resource ID of the UAMI (useful for pod identity spec).')
output uamiResourceId string = uami.id
