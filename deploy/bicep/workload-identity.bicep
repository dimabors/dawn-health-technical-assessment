// Per-environment workload identity stack.
//
// Deploys, for EACH environment in `environments`:
//   - Key Vault (RBAC mode, soft-delete on)
//   - User-Assigned Managed Identity (UAMI)
//   - Federated credential trusting the K8s ServiceAccount on the AKS OIDC issuer
//   - Key Vault Secrets User role assignment (UAMI -> KV) for read-only access
//
// One template, one deployment, all envs at once. Idempotent.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string = resourceGroup().location

@description('Existing AKS cluster name (read its OIDC issuer).')
param aksClusterName string = 'aks-shared'

@description('Environments to deploy.')
param environments array = [
  'dev'
  'staging'
  'prod'
]

@description('K8s ServiceAccount name the workload runs as (same in every env).')
param serviceAccountName string = 'team-alpha-workload-sa'

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksClusterName
}

// One module per environment to keep the template flat and avoid name collisions.
module envStack 'modules/wi-env.bicep' = [for env in environments: {
  name: 'wi-${env}'
  params: {
    environment: env
    location: location
    oidcIssuerUrl: aks.properties.oidcIssuerProfile.issuerURL
    serviceAccountName: serviceAccountName
  }
}]

output environments array = [for (env, i) in environments: {
  environment: env
  namespace: envStack[i].outputs.namespaceName
  keyVaultName: envStack[i].outputs.keyVaultName
  uamiClientId: envStack[i].outputs.uamiClientId
  uamiResourceId: envStack[i].outputs.uamiResourceId
}]
