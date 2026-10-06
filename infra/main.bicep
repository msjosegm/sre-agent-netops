targetScope = 'subscription'

@description('Resource group único que contendrá toda la demo.')
@allowed([
  'rg-sreagent-netops'
])
param resourceGroupName string = 'rg-sreagent-netops'

@allowed([
  'swedencentral'
])
param location string = 'swedencentral'

@description('Clave pública SSH para las VM de tráfico. No se crean IP públicas.')
param adminSshPublicKey string

@description('Usuario administrador local de las VM.')
param adminUsername string = 'azureuser'

@description('Tamaño de las VM de prueba.')
param vmSize string = 'Standard_D2as_v5'

@description('Nombre del Azure SRE Agent.')
param sreAgentName string = 'sre-netops-demo-sc'

@description('Proveedor de modelo habilitado para la suscripción en Sweden Central.')
@allowed([
  'MicrosoftFoundry'
  'Anthropic'
])
param sreModelProvider string = 'MicrosoftFoundry'

@description('Etiquetas comunes.')
param tags object = {
  environment: 'demo'
  workload: 'sreagent-netops'
  region: 'swedencentral'
  managedBy: 'bicep'
}

resource demoRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module platform './modules/platform.bicep' = {
  name: 'deploy-sreagent-netops'
  scope: demoRg
  params: {
    location: location
    adminSshPublicKey: adminSshPublicKey
    adminUsername: adminUsername
    vmSize: vmSize
    sreAgentName: sreAgentName
    sreModelProvider: sreModelProvider
    tags: tags
  }
}

output resourceGroupName string = demoRg.name
output resourceGroupId string = demoRg.id
output sreAgentName string = sreAgentName
output sreAgentId string = platform.outputs.sreAgentId
output sreAgentEndpoint string = platform.outputs.sreAgentEndpoint
output firewallPrivateIp string = platform.outputs.firewallPrivateIp
output spoke1VmPrivateIp string = platform.outputs.spoke1VmPrivateIp
output spoke2VmPrivateIp string = platform.outputs.spoke2VmPrivateIp
output logAnalyticsWorkspaceId string = platform.outputs.logAnalyticsWorkspaceId
