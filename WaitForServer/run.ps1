using namespace System.Net
using namespace System.Web
#region Init
param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

# Grab variables from Function Application Settings
$ACIResourceGroup   = 'MinecraftACI'
$ContainerGroupName = $env:CONTAINER_GROUP_NAME
$KeyVaultName       = $env:KEY_VAULT_NAME
$DnsZoneName        = $env:DNS_ZONE_NAME
$DnsRecordName      = $env:DNS_RECORD_NAME

# Get required inputs from request body
$Body       = $Request.Body.Split('&') | ConvertFrom-StringData
$ServerName = [HttpUtility]::UrlDecode($Body.ServerName)
$Requestor  = [HttpUtility]::UrlDecode($Body.Requestor)
#endregion Init

#region Functions
function Test-RCDNetConnection {
    <#
        .SYNOPSIS
            Test connection to a specified endpoint on a specified TCP port
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # IP Address or FQDN of endpoint to test
        [Parameter(Mandatory)]
        [string] $ComputerName,

        # TCP port to connect over
        [Parameter(Mandatory)]
        [int] $Port,

        # Timeout to wait for response from endpoint (in ms)
        [Parameter()]
        [int] $Timeout = 3000
    )
    process {
        Write-Verbose "[VERBOSE] Testing the connection to $ComputerName on port $Port with a timeout of $Timeout milliseconds"
        Write-Verbose '[VERBOSE] Create new TCP Client and open connection to endpoint'
        $TcpClient     = New-Object Sockets.TcpClient
        $TcpConnection = $TcpClient.BeginConnect($ComputerName, $Port, $null, $null)

        Write-Verbose '[VERBOSE] Wait for connection or timeout, return when either is true'
        $Connection    = $TcpConnection.AsyncWaitHandle.WaitOne($Timeout, $false)

        if ($Connection) {
            try {
                $TcpClient.EndConnect($TcpConnection)
                $PortOpen = $true
                Write-Verbose "[VERBOSE] Connection to $ComputerName on port $Port succeeded"
            } catch {
                $PortOpen = $false
                Write-Verbose "[VERBOSE] Connection to $ComputerName on port $Port failed: $($_.Exception.Message.Split('(s): ')[1])"
            }
        } else {
            $PortOpen = $false
            Write-Verbose "[VERBOSE] Connection to $ComputerName on port $Port failed: `"Connection timed out after $($Timeout)ms`""
        }

        Write-Verbose '[VERBOSE] Close and Dispose of TCP Client'
        $TcpClient.Close()
        $TcpClient.Dispose()

        return $PortOpen
    }
} #endFunction Test-RCDNetConnection
#endregion Functions

if ([string]::IsNullOrWhiteSpace($ServerName)) {
    Write-Error '[ERROR] Missing Required parameter ServerName. Please provide a value that is not null, empty, or whitespace'
    return
} elseif ([string]::IsNullOrWhiteSpace($Requestor)) {
    Write-Error '[ERROR] Missing Required parameter Requestor. Please provide a value that is not null, empty, or whitespace'
    return
} else {
    Write-Output "[INFO] Waiting for [$ContainerGroupName] with IP address [$ServerName] to become available based on request from [$Requestor]"
}

#region WaitForServer
try {
    $RConPassword = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ContainerGroupName-RconPassword" -AsPlainText
} catch {
    Write-Error "[ERROR] Error getting Azure Key Vault Secret [$ContainerGroupName-RconPassword] from Azure Key Vault [$KeyVaultName]: $_"
}

$Count = 0
do {
    $Status = Test-RCDNetConnection -ComputerName $ServerName -Port 25575 -Timeout 5000 # Time out after waiting 5 seconds
    $Count++
} until ($Status -or ($Count -eq 48))

# Time out after waiting 4 minutes
if ($Count -eq 48) {
    Write-Error "[ERROR] Timed out waiting for Azure Container Group [$ContainerGroupName] to become available"
    return
}

Write-Output "[INFO] Waiting for [$ContainerGroupName] to start and build world"
$Count = 0
do {
    try {
        $Status = Invoke-Expression ".\mcrcon.exe -H $ServerName -P 25575 -p $RconPassword 'list'" 2>&1
    } catch {
        ;
    }
    $Count++
    Start-Sleep -Seconds 8 # Command takes ~2 seconds to fail, add 8 seconds to create ~10 second iterations
    Write-Output "[INFO] $($Count * 10) seconds elapsed..."
} until (($Status -like 'There are *') -or ($Count -eq 24))

# Time out after waiting 4 minutes
if ($Count -eq 24) {
    Write-Error "[ERROR] Timed out waiting for server [$ContainerGroupName] to start"
    return
}
#endregion WaitForServer

#region UpdateDNS
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
    Write-Output "[INFO] Getting Azure Public DNS Record Set [$DnsRecordName] in Zone [$($DnsZone.Name)]"
    $RecordSet = Get-AzDnsRecordSet -ResourceGroupName $DnsZone.ResourceGroupName -ZoneName $DnsZone.Name -Name $DnsRecordName -RecordType A
} catch {
    Write-Error "[ERROR] Error getting Azure DNS Record Set with name [$DnsRecordName] in Zone [$($DnsZone.Name)]: $_"
}

try {
    $RecordSet.Records[0].Ipv4Address = $ServerName
    Set-AzDnsRecordSet -RecordSet $RecordSet -Overwrite
    Write-Output "[INFO] Updated Azure DNS Record Set [$DnsRecordName] IP address to [$ServerName]: $_"
} catch {
    Write-Error "[ERROR] Error updating Azure DNS Record Set [$DnsRecordName] IP address to [$ServerName]: $_"
}
#endregion UpdateDNS

#region Output
try {
    # Get Twilio connection secrets from Azure Key Vault
    $TwilioSid      = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-SID' -AsPlainText
    $TwilioToken    = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-Token').SecretValue
    $TwilioPhone    = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-PhoneNumber' -AsPlainText
    $TwilioEndpoint = "https://api.twilio.com/2010-04-01/Accounts/$TwilioSid/Messages.json"
    $TwilioCred     = New-Object System.Management.Automation.PsCredential($TwilioSid, $TwilioToken)
} catch {
    Write-Error "[ERROR] Error getting Twilio secrets from Azure Key Vault [$KeyVaultName]: $_"
}

# Build Twilio request body
$SMS = @{
    From = $TwilioPhone
    To   = $Requestor
    Body = "Minecraft server '$DnsRecordName.$DnsZoneName' ($ServerName) started successfully."
}

try {
    # Invoke Twilio API to send text message
    Write-Output "[INFO] Sending Twilio text to [$Requestor]"
    Invoke-RestMethod -Method Post -Uri $TwilioEndpoint -Credential $TwilioCred -Body $SMS | Select-Object sid, body
} catch {
    Write-Error "[ERROR] Error invoking Twilio API: $_"
    return
}

# Send HTTP response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = "[INFO] Successfully started Azure Container Group [$ContainerGroupName]. Access at '$DnsRecordName.$DnsZoneName' ($ServerName)"
})
#endregion Output