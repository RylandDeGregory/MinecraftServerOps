using namespace System.Net
#region Init
param($Timer)

$ErrorActionPreference = 'Stop'

# Grab variables from Function Application Settings
$ACIResourceGroup   = 'MinecraftACI'
$ContainerGroupName = $env:CONTAINER_GROUP_NAME
$KeyVaultName       = $env:KEY_VAULT_NAME
$StorageAccountName = $env:STORAGE_ACCOUNT_NAME

# Define message that will be returned when no players are online, for comparison against RCON responses
$EmptyMessage = 'There are 0 of a max of 20 players online: '

# Multiply by 5 mins to get total length of empty time before shutdown
$Max = 4
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

#region Connect
try {
    # Connect to Azure Storage Table
    $AccountKey = Get-AzStorageAccountKey -ResourceGroupName $ACIResourceGroup -Name $StorageAccountName | Select-Object -First 1 -ExpandProperty Value
    $Context    = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $AccountKey
    $Table      = Get-AzStorageTable -Context $Context -Name 'ActiveUsers' | Select-Object -ExpandProperty CloudTable
} catch {
    Write-Error "[ERROR] Error connecting to Storage Account: $_"
}

try {
    # Get RCON password from Azure Key Vault
    $RConPassword = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ContainerGroupName-RconPassword" -AsPlainText
} catch {
    Write-Error "[ERROR] Error getting Azure Key Vault Secret [$ContainerGroupName-RconPassword] from Azure Key Vault [$KeyVaultName]: $_"
}
#endregion Connect

#region Process
try {
    # Get Container Group resource to obtain IP address
    $ContainerGroup = Get-AzContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName
} catch {
    Write-Error "[ERROR] Error getting Azure Container Group with name [$ContainerGroupName] in Resource Group [$ACIResourceGroup]: $_"
}

if (-not $ContainerGroup.IPAddressIP) {
    Write-Error "[ERROR] Error determining Container Group IP. State: [$($ContainerGroup.InstanceViewState)]"
}

Write-Output "[INFO] Checking the number of active players in [$ContainerGroupName]..."
# If the server is online, query the list of active users with mcrcon.
if (Test-RCDNetConnection -ComputerName $ContainerGroup.IPAddressIP -Port 25575) {
    $NumPlayers = Invoke-Expression ".\mcrcon.exe -H $($ContainerGroup.IPAddressIP) -P 25575 -p $RconPassword 'list'"
    if ($NumPlayers -eq $EmptyMessage) {
        # If there are no players on the server, add a record to an Azure Storage Table that tracks the number of increments while empty
        Write-Output "[INFO] There are 0 active players in [$ContainerGroupName]. Checking number of iterations while empty."
        $Rows = (Get-AzTableRow -Table $Table).Count

        if ($Rows -lt $Max) {
            Write-Output "[INFO] Azure Container Group [$ContainerGroupName] has been empty for [$($Rows * 5) minutes]. Updating Iterations."
            $Rows++
            Add-AzTableRow -Table $Table -PartitionKey 'default' -RowKey $Rows | Select-Object -ExpandProperty Result
        } else {
            try {
                # If the server has been empty for longer than the pre-defined maximum, stop the Container Group
                Write-Output "[INFO] Azure Container Group [$ContainerGroupName] has been empty for longer than [$($Max * 5) minutes]. Stopping Container Group."
                Stop-AZContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName
            } catch {
                Write-Error "[ERROR] Error stopping Azure Container Group [$ContainerGroupName]: $_"
            }
            try {
                # Remove all records from the Azure Storage Table to reset the iteration counter
                Get-AzTableRow -Table $Table | Remove-AzTableRow -Table $Table | Out-Null
            } catch {
                Write-Error "[ERROR] Error removing Azure Table entities: $_"
            }
        }
    } else {
        Write-Output "[INFO] $NumPlayers"
    }
} else {
    Write-Output "[INFO] Azure Container Group [$ContainerGroupName] is offline"
}
#endregion Process