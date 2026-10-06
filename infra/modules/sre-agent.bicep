param agentName string
param location string
param logAnalyticsWorkspaceId string
param appInsightsAppId string
@secure()
param appInsightsConnectionString string
@allowed([
  'MicrosoftFoundry'
  'Anthropic'
])
param modelProvider string
param tags object

var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var logAnalyticsReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
var sreAgentAdminRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${agentName}'
  location: location
  tags: tags
  properties: {
    isolationScope: 'Regional'
  }
}

resource uamiReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, agentIdentity.id, readerRoleId)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource uamiLogReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, agentIdentity.id, logAnalyticsReaderRoleId)
  properties: {
    roleDefinitionId: logAnalyticsReaderRoleId
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource uamiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, agentIdentity.id, contributorRoleId)
  properties: {
    roleDefinitionId: contributorRoleId
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${agentIdentity.id}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: agentIdentity.id
      managedResources: [
        resourceGroup().id
      ]
    }
    actionConfiguration: {
      accessLevel: 'High'
      identity: agentIdentity.id
      mode: 'Autonomous'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
    incidentManagementConfiguration: {
      type: 'AzMonitor'
    }
    upgradeChannel: 'Preview'
    monthlyAgentUnitLimit: 1000
    defaultModel: {
      provider: modelProvider
      name: 'Automatic'
    }
    experimentalSettings: {
      EnableWorkspaceTools: true
      EnableHttpTriggers: true
      EnableV2AgentLoop: true
    }
  }
  dependsOn: [
    uamiReader
    uamiLogReader
    uamiContributor
  ]
}

resource systemReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreAgent.id, readerRoleId)
  properties: {
    roleDefinitionId: readerRoleId
    principalId: sreAgent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource systemLogReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreAgent.id, logAnalyticsReaderRoleId)
  properties: {
    roleDefinitionId: logAnalyticsReaderRoleId
    principalId: sreAgent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource systemContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, sreAgent.id, contributorRoleId)
  properties: {
    roleDefinitionId: contributorRoleId
    principalId: sreAgent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deployerAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, deployer().objectId, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: sreAgentAdminRoleId
    principalId: deployer().objectId
    principalType: 'User'
  }
}

#disable-next-line BCP081
resource logAnalyticsConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = {
  parent: sreAgent
  name: 'log-analytics-netops'
  properties: {
    dataConnectorType: 'LogAnalytics'
    dataSource: logAnalyticsWorkspaceId
    extendedProperties: {
      armResourceId: logAnalyticsWorkspaceId
      resource: {
        name: last(split(logAnalyticsWorkspaceId, '/'))
      }
    }
    identity: 'system'
  }
  dependsOn: [
    systemLogReader
  ]
}

#disable-next-line BCP081
resource azureMonitorConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = {
  parent: sreAgent
  name: 'azure-monitor-netops'
  properties: {
    dataConnectorType: 'AzureMonitor'
    dataSource: subscription().id
    extendedProperties: {
      armResourceId: subscription().id
      lookbackDays: 7
    }
    identity: 'system'
  }
  dependsOn: [
    systemReader
  ]
}

output agentId string = sreAgent.id
output agentEndpoint string = sreAgent.properties.agentEndpoint
output managedIdentityId string = agentIdentity.id
output userAssignedPrincipalId string = agentIdentity.properties.principalId
output systemAssignedPrincipalId string = sreAgent.identity.principalId
