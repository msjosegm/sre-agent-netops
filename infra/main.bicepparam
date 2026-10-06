using './main.bicep'

param resourceGroupName = 'rg-sreagent-netops'
param location = 'swedencentral'
param adminSshPublicKey = readEnvironmentVariable('ADMIN_SSH_PUBLIC_KEY')
param adminUsername = 'azureuser'
param vmSize = 'Standard_D2as_v5'
param sreAgentName = 'sre-netops-demo-sc'
param sreModelProvider = 'MicrosoftFoundry'
param tags = {
  environment: 'demo'
  workload: 'sreagent-netops'
  region: 'swedencentral'
  managedBy: 'bicep'
  owner: 'netops'
}
