using namespace System.Management
#region Init
param($QueueItem, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

# Grab variables from Function Application Settings
$ACIResourceGroup      = 'MinecraftACI'
$ContainerGroupName    = $env:CONTAINER_GROUP_NAME
$DnsZoneName           = $env:DNS_ZONE_NAMEå
$DnsRecordName         = $env:DNS_RECORD_NAME
$FunctionKeySecretName = $env:WAIT_FUNCTION_KEY
$KeyVaultName          = $env:KEY_VAULT_NAME
$StorageAccountName    = $env:STORAGE_ACCOUNT_NAME

# Grab variables from Azure Storage Queue message
$From    = $QueueItem.Requestor
$Message = $QueueItem.Message
#endregion Init

#region Connect
try {
    # Connect to Azure Storage Table
    $AccountKey = Get-AzStorageAccountKey -ResourceGroupName $ACIResourceGroup -Name $StorageAccountName | Select-Object -First 1 -ExpandProperty Value
    $Context    = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $AccountKey
    $Table      = Get-AzStorageTable -Context $Context -Name 'ValidUsers' | Select-Object -ExpandProperty CloudTable
    $Users      = Get-AzTableRow -Table $Table
} catch {
    Write-Error "[ERROR] Error connecting to Storage Account: $_"
}

try {
    # Get Twilio connection secrets from Azure Key Vault
    $TwilioSid      = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-SID' -AsPlainText
    $TwilioToken    = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-Token').SecretValue
    $TwilioPhone    = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'Twilio-PhoneNumber' -AsPlainText
    $TwilioEndpoint = "https://api.twilio.com/2010-04-01/Accounts/$TwilioSid/Messages.json"
    $TwilioCred     = New-Object Automation.PsCredential($TwilioSid, $TwilioToken)
} catch {
    Write-Error "[ERROR] Error getting Twilio secrets from Azure Key Vault [$($KeyVaultName)]: $_"
}
#endregion Connect

#region Validate
# Send response message to requestor if their phone number is not in the ValidUsers Azure Storage Table
if ($From -notin $Users.PhoneNumber) {
    try {
        # Build Twilio request body
        $SMS = @{
            From = $TwilioPhone
            To   = $From
            Body = 'You are not authorized to use this service. Please contact the administrator to gain access.'
        }

        # Invoke Twilio API to send text message
        Invoke-RestMethod -Method Post -Uri $TwilioEndpoint -Credential $TwilioCred -Body $SMS | Select-Object sid, body
    } catch {
        Write-Error "[ERROR] Error invoking Twilio API: $_"
        return
    }
    Write-Error "[ERROR] Unauthorized user [$From]"
    return
}
#endregion Validate

#region Process
if ($Message -eq 'Start') {
    # Start the Azure Container Group
    Write-Output "[INFO] Server start request received from [$From]"
    Start-AzContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName -NoWait -ErrorAction SilentlyContinue

    # Get Container Group's status
    $ContainerGroup = Get-AzContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName

    # Loop until Container Group is running
    Write-Output "[INFO] Waiting for Azure Container Group [$ContainerGroupName] to start"
    $Count = 0
    do {
        $ContainerGroup = Get-AzContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName
        $Count++
        Start-Sleep -Seconds 10
        Write-Output "[INFO] $($Count * 10) seconds elapsed..."
    } until (($ContainerGroup.InstanceViewState -eq 'Running') -or ($Count -eq 24))

    # Time out after waiting 4 minutes
    if ($Count -eq 24) {
        Write-Error "[ERROR] Timed out waiting for Azure Container Group [$ContainerGroupName] to start"
        return
    }

    # Get updated Container Group properties
    $ContainerGroup = Get-AzContainerGroup -ResourceGroupName $ACIResourceGroup -Name $ContainerGroupName
    if ([string]::IsNullOrWhiteSpace($ContainerGroup.IPAddressIP)) {
        Write-Error "[ERROR] Error getting IP address of Azure Container Group [$ContainerGroupName]"
    }

    try {
        # Invoke WaitForServer function
        $FunctionKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -SecretName $FunctionKeySecretName -AsPlainText
        $Body = @{
            ServerName = $ContainerGroup.IPAddressIP
            Requestor  = $From
        }
        Write-Output "[INFO] Invoking WaitForServer function to track the status of [$ContainerGroupName]"
        Invoke-RestMethod -Method Post -Uri "https://mc-server-ops.azurewebsites.net/api/waitforserver?code=$FunctionKey" -Body $Body
    } catch {
        Write-Error "[ERROR] Error starting WaitForServer function: $_"
    }
} elseif ($Message -eq 'Shutdown') {
    try {
        # Stop Azure Container Group
        Write-Output "[INFO] Server stop request received from [$From]"
        Stop-AzContainerGroup -ResourceGroupName MinecraftACI -Name $ContainerGroupName -Confirm:$false
    } catch {
        Write-Error "[ERROR] Error stopping Azure Container Group [$ContainerGroupName]: $_"
    }
    try {
        # Build Twilio request body
        $SMS = @{
            From = $TwilioPhone
            To   = $From
            Body = "Minecraft server '$DnsRecordName.$DnsZoneName' stopped successfully."
        }

        # Invoke Twilio API to send text message
        Invoke-RestMethod -Method Post -Uri $TwilioEndpoint -Credential $TwilioCred -Body $SMS | Select-Object sid, body
    } catch {
        Write-Error "[ERROR] Error invoking Twilio API: $_"
        return
    }
} elseif ($Message -eq 'Stop') {
    Write-Output "[INFO] User [$From] requested to opt-out of future communications."
} else {
    Write-Error "[ERROR] Received invalid message body: $Message"
}
#endregion Process