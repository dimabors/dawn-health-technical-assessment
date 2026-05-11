// Platform (shared across all envs) — ACR + AKS with OIDC issuer + workload identity.
//
// Scope: resource group. The RG itself is created once with `az group create`
// (or via `Initial-Deploy.md`); everything else, including the AcrPull role
// assignment that ties AKS to ACR, is here.
//
// Why properties over CLI flags:
//   `az aks create --enable-oidc-issuer` silently no-ops if the resource
//   provider returns success without setting the field. Bicep makes both
//   flags first-class properties so what you write is what you get.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string = resourceGroup().location

@description('AKS cluster name.')
param aksClusterName string = 'aks-shared'

@description('ACR name (must be globally unique, lowercase alphanumeric).')
param acrName string = 'ecapacr'

@description('Node pool VM size. northeurope rejects Standard_B2s; use B2s_v2.')
param nodeVmSize string = 'Standard_B2s_v2'

@description('Node count.')
@minValue(1)
@maxValue(10)
param nodeCount int = 1

@description('Kubernetes version. Empty = default channel.')
param kubernetesVersion string = ''

@description('AKS DNS prefix. Cannot be changed after cluster creation. If you bootstrapped the cluster with `az aks create` earlier, set this to match the existing value (run: `az aks show --query dnsPrefix`). Default mirrors the az-CLI auto-generated form.')
param dnsPrefix string = '${aksClusterName}-${resourceGroup().name}-${take(subscription().subscriptionId, 6)}'

// 1. ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// 2. AKS — system-assigned identity, OIDC + workload identity ON at create.
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: aksClusterName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    enableRBAC: true
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
      }
    ]
  }
}

// 3. AcrPull on ACR for the AKS kubelet identity (replaces `--attach-acr`).
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPullForKubelet 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, aks.id, acrPullRoleId)
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      acrPullRoleId
    )
  }
}

output aksClusterName string = aks.name
output aksOidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
