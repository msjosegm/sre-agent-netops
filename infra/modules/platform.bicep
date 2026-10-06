param location string
param adminSshPublicKey string
param adminUsername string
param vmSize string
param sreAgentName string
param sreModelProvider string
param tags object

var suffix = 'sre-netops-sc'
var hubVnetName = 'vnet-hub-${suffix}'
var spoke1VnetName = 'vnet-spoke1-${suffix}'
var spoke2VnetName = 'vnet-spoke2-${suffix}'
var hubPrefix = '10.0.0.0/16'
var spoke1Prefix = '10.1.0.0/16'
var spoke2Prefix = '10.2.0.0/16'
var spoke1SubnetPrefix = '10.1.1.0/24'
var spoke2SubnetPrefix = '10.2.1.0/24'
var firewallPrivateIp = '10.0.0.4'
var spoke1VmPrivateIp = '10.1.1.4'
var spoke2VmPrivateIp = '10.2.1.4'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Request_Source: 'SreAgent'
    WorkspaceResourceId: law.id
  }
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
        }
      }
    ]
  }
}

resource spoke1Asg 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-app-spoke1-${suffix}'
  location: location
  tags: tags
}

resource spoke2Asg 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-app-spoke2-${suffix}'
  location: location
  tags: tags
}

resource spoke1Nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-app-spoke1-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-Spoke2'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: spoke2Prefix
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [
            {
              id: spoke1Asg.id
            }
          ]
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource spoke2Nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-app-spoke2-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-Spoke1'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: spoke1Prefix
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [
            {
              id: spoke2Asg.id
            }
          ]
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-afw-${suffix}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: 'afwp-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    dnsSettings: {
      enableProxy: true
    }
  }
}

resource firewallPolicyRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: firewallPolicy
  name: 'rcg-netops'
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'rc-allow-east-west'
        priority: 200
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'Allow-Spoke1-To-Spoke2-HTTP'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              spoke1Prefix
            ]
            destinationAddresses: [
              spoke2Prefix
            ]
            destinationPorts: [
              '8080'
            ]
          }
          {
            name: 'Allow-Spoke2-To-Spoke1-HTTP'
            ruleType: 'NetworkRule'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              spoke2Prefix
            ]
            destinationAddresses: [
              spoke1Prefix
            ]
            destinationPorts: [
              '8080'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'afw-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    threatIntelMode: 'Alert'
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'AzureFirewallSubnet')
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [
    firewallPolicyRules
  ]
}

resource spoke1RouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-spoke1-${suffix}'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-spoke2-via-firewall'
        properties: {
          addressPrefix: spoke2Prefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

resource spoke2RouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-spoke2-${suffix}'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-spoke1-via-firewall'
        properties: {
          addressPrefix: spoke1Prefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spoke1VnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke1Prefix
      ]
    }
    subnets: [
      {
        name: 'snet-app-spoke1'
        properties: {
          addressPrefix: spoke1SubnetPrefix
          networkSecurityGroup: {
            id: spoke1Nsg.id
          }
          routeTable: {
            id: spoke1RouteTable.id
          }
        }
      }
    ]
  }
}

resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spoke2VnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke2Prefix
      ]
    }
    subnets: [
      {
        name: 'snet-app-spoke2'
        properties: {
          addressPrefix: spoke2SubnetPrefix
          networkSecurityGroup: {
            id: spoke2Nsg.id
          }
          routeTable: {
            id: spoke2RouteTable.id
          }
        }
      }
    ]
  }
}

resource hubToSpoke1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke1'
  properties: {
    remoteVirtualNetwork: {
      id: spoke1Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spoke1ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke1Vnet
  name: 'peer-spoke1-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource hubToSpoke2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke2'
  properties: {
    remoteVirtualNetwork: {
      id: spoke2Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spoke2ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke2Vnet
  name: 'peer-spoke2-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spoke1Nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-spoke1-${suffix}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: spoke1VmPrivateIp
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', spoke1Vnet.name, 'snet-app-spoke1')
          }
          applicationSecurityGroups: [
            {
              id: spoke1Asg.id
            }
          ]
        }
      }
    ]
  }
}

resource spoke2Nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-vm-spoke2-${suffix}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: spoke2VmPrivateIp
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', spoke2Vnet.name, 'snet-app-spoke2')
          }
          applicationSecurityGroups: [
            {
              id: spoke2Asg.id
            }
          ]
        }
      }
    ]
  }
}

var spoke1CloudInitTemplate = '''
#cloud-config
write_files:
  - path: /opt/netops/index.html
    permissions: '0644'
    content: |
      Azure SRE Agent NetOps demo - spoke1
  - path: /etc/systemd/system/netops-web.service
    permissions: '0644'
    content: |
      [Unit]
      Description=NetOps demo web endpoint
      After=network-online.target
      [Service]
      WorkingDirectory=/opt/netops
      ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0
      Restart=always
      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/netops-probe.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      ts=$(date -u +%FT%TZ)
      if curl --max-time 5 --silent --fail http://__TARGET_IP__:8080/ >/dev/null; then
        echo "$ts target=__TARGET_IP__:8080 result=success"
      else
        echo "$ts target=__TARGET_IP__:8080 result=failure"
      fi
  - path: /etc/systemd/system/netops-probe.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Probe spoke2 through Azure Firewall
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/netops-probe.sh
      StandardOutput=append:/var/log/netops-probe.log
      StandardError=append:/var/log/netops-probe.log
  - path: /etc/systemd/system/netops-probe.timer
    permissions: '0644'
    content: |
      [Unit]
      Description=Run NetOps probe every minute
      [Timer]
      OnBootSec=1min
      OnUnitActiveSec=1min
      [Install]
      WantedBy=timers.target
runcmd:
  - mkdir -p /opt/netops
  - systemctl daemon-reload
  - systemctl enable --now netops-web.service
  - systemctl enable --now netops-probe.timer
'''

var spoke1CloudInit = replace(spoke1CloudInitTemplate, '__TARGET_IP__', spoke2VmPrivateIp)

var spoke2CloudInitTemplate = '''
#cloud-config
write_files:
  - path: /opt/netops/index.html
    permissions: '0644'
    content: |
      Azure SRE Agent NetOps demo - spoke2
  - path: /etc/systemd/system/netops-web.service
    permissions: '0644'
    content: |
      [Unit]
      Description=NetOps demo web endpoint
      After=network-online.target
      [Service]
      WorkingDirectory=/opt/netops
      ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0
      Restart=always
      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/netops-probe.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      ts=$(date -u +%FT%TZ)
      if curl --max-time 5 --silent --fail http://__TARGET_IP__:8080/ >/dev/null; then
        echo "$ts target=__TARGET_IP__:8080 result=success"
      else
        echo "$ts target=__TARGET_IP__:8080 result=failure"
      fi
  - path: /etc/systemd/system/netops-probe.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Probe spoke1 through Azure Firewall
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/netops-probe.sh
      StandardOutput=append:/var/log/netops-probe.log
      StandardError=append:/var/log/netops-probe.log
  - path: /etc/systemd/system/netops-probe.timer
    permissions: '0644'
    content: |
      [Unit]
      Description=Run NetOps probe every minute
      [Timer]
      OnBootSec=1min
      OnUnitActiveSec=1min
      [Install]
      WantedBy=timers.target
runcmd:
  - mkdir -p /opt/netops
  - systemctl daemon-reload
  - systemctl enable --now netops-web.service
  - systemctl enable --now netops-probe.timer
'''

var spoke2CloudInit = replace(spoke2CloudInitTemplate, '__TARGET_IP__', spoke1VmPrivateIp)

resource spoke1Vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-app-spoke1-${suffix}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-spoke1'
      adminUsername: adminUsername
      customData: base64(spoke1CloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spoke1Nic.id
        }
      ]
    }
  }
}

resource spoke2Vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-app-spoke2-${suffix}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-spoke2'
      adminUsername: adminUsername
      customData: base64(spoke2CloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spoke2Nic.id
        }
      ]
    }
  }
}

resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-afw-to-log'
  scope: firewall
  properties: {
    workspaceId: law.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

module alerts './alerts.bicep' = {
  name: 'deploy-netops-alerts'
  params: {
    location: location
    logAnalyticsWorkspaceId: law.id
    tags: tags
  }
  dependsOn: [
    firewallDiagnostics
  ]
}

module agent './sre-agent.bicep' = {
  name: 'deploy-sre-agent'
  params: {
    agentName: sreAgentName
    location: location
    logAnalyticsWorkspaceId: law.id
    appInsightsAppId: appInsights.properties.AppId
    appInsightsConnectionString: appInsights.properties.ConnectionString
    modelProvider: sreModelProvider
    tags: tags
  }
}

output sreAgentId string = agent.outputs.agentId
output sreAgentEndpoint string = agent.outputs.agentEndpoint
output firewallPrivateIp string = firewallPrivateIp
output spoke1VmPrivateIp string = spoke1VmPrivateIp
output spoke2VmPrivateIp string = spoke2VmPrivateIp
output logAnalyticsWorkspaceId string = law.id
output agentUserAssignedPrincipalId string = agent.outputs.userAssignedPrincipalId
output agentSystemAssignedPrincipalId string = agent.outputs.systemAssignedPrincipalId
output firewallDenyAlertId string = alerts.outputs.firewallDenyAlertId
