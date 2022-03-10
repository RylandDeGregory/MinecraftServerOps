#region Init
param($eventGridEvent, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

# Grab variables from Function Application Settings
$ACIResourceGroup   = 'MinecraftACI'
$ContainerGroupName = $env:CONTAINER_GROUP_NAME
$DnsZoneName        = $env:DNS_ZONE_NAME
$DnsRecordName      = $env:DNS_RECORD_NAME
#endregion Init

#region Process
try {
    Write-Output "[INFO] Getting Azure DNS Zone [$DnsZoneName]"
    $DnsZone = Get-AzDnsZone | Where-Object { $_.Name -eq $DnsZoneName }
} catch {
    Write-Error "[ERROR] Error getting Azure DNS Zone with name [$DnsZoneName]: $_"
}

if (-not $DnsZone) {
    Write-Error "[ERROR] No DNS Zone found with name [$DnsZoneName]"
}

try {
    Write-Output "[INFO] Getting updated public IP address for Azure Container Group [$ContainerGroupName]"
    $ContainerGroup = Get-AzContainerGroup -Name $ContainerGroupName -ResourceGroupName $ACIResourceGroup
    $ContainerGroupIP = $ContainerGroup.IPAddressIP
} catch {
    Write-Error "[ERROR] Error getting Azure Container Group with name [$ContainerGroupName]: $_"
}

if (-not $ContainerGroupIP) {
    if ($ContainerGroup.InstanceViewState -eq 'Running') {
        Write-Error "[ERROR] Error getting IP address of Azure Container Group [$ContainerGroupName]"
    } else {
        Write-Output "[INFO] Azure Container Group [$ContainerGroupName] is [$($ContainerGroup.InstanceViewState)]"
    }
}

try {
    Write-Output "[INFO] Getting Azure Public DNS Record Set [$DnsRecordName] in Zone [$($DnsZone.Name)]"
    $RecordSet = Get-AzDnsRecordSet -ResourceGroupName $DnsZone.ResourceGroupName -ZoneName $DnsZone.Name -Name $DnsRecordName -RecordType A
} catch {
    Write-Error "[ERROR] Error getting Azure DNS Record Set with name [$DnsRecordName] in Zone [$($DnsZone.Name)]: $_"
}

try {
    $RecordSet.Records[0].Ipv4Address = $ContainerGroupIP
    Set-AzDnsRecordSet -RecordSet $RecordSet -Overwrite
    Write-Output "[INFO] Updated Azure DNS Record Set [$DnsRecordName] IP address to [$ContainerGroupIP]: $_"
} catch {
    Write-Error "[ERROR] Error updating Azure DNS Record Set [$DnsRecordName] IP address to [$ContainerGroupIP]: $_"
}
#endregion Process