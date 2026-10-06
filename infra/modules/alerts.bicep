param location string
param logAnalyticsWorkspaceId string
param tags object

resource firewallDenyAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-sre-netops-east-west-deny'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE NetOps East-West Firewall Deny'
    description: 'Detecta tráfico TCP/8080 denegado por Azure Firewall entre los dos spokes de la demo.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    skipQueryValidation: true
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT1M'
    }
    checkWorkspaceAlertsStorageConfigured: false
    criteria: {
      allOf: [
        {
          query: '''
AZFWNetworkRule
| where TimeGenerated > ago(5m)
| where Action =~ "Deny"
| where tostring(DestinationPort) == "8080"
| where
    (SourceIp startswith "10.1." and DestinationIp startswith "10.2.")
    or
    (SourceIp startswith "10.2." and DestinationIp startswith "10.1.")
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: []
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: []
      customProperties: {
        demo: 'sreagent-netops'
        runbook: 'network-triage'
        resourceGroup: 'rg-sreagent-netops'
      }
    }
  }
}

output firewallDenyAlertId string = firewallDenyAlert.id
