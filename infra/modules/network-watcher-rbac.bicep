targetScope = 'resourceGroup'

param networkWatcherName string = 'NetworkWatcher_swedencentral'
param userAssignedPrincipalId string
param systemAssignedPrincipalId string

var networkContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4d97b98b-1d4f-4787-a291-c67834d212e7'
)

resource networkWatcher 'Microsoft.Network/networkWatchers@2024-05-01' existing = {
  name: networkWatcherName
}

resource userAssignedNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(networkWatcher.id, userAssignedPrincipalId, networkContributorRoleId)
  scope: networkWatcher
  properties: {
    roleDefinitionId: networkContributorRoleId
    principalId: userAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource systemAssignedNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(networkWatcher.id, systemAssignedPrincipalId, networkContributorRoleId)
  scope: networkWatcher
  properties: {
    roleDefinitionId: networkContributorRoleId
    principalId: systemAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
}
