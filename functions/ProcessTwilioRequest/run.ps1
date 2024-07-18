using namespace System.Net
using namespace System.Web
#region Init
param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'
$Valid = $true

# Grab variables from Function Application Settings
$DnsZoneName   = $env:DNS_ZONE_NAME
$DnsRecordName = $env:DNS_RECORD_NAME

# Get required inputs from request body
$Body    = $Request.Body.Split('&') | ConvertFrom-StringData
$From    = [HttpUtility]::UrlDecode($Body.From)
$Message = [HttpUtility]::UrlDecode($Body.Body)

# Remove any leading or trailing whitespace
$Message = $Message.Trim()
#endregion Init

#region Process
# Check if the message contains a valid command and respond to the sender
if ($Message -notin 'Start', 'Shutdown') {
    $Response = "<Response><Message>Invalid Request. Valid commands are 'Start' and 'Shutdown'.</Message></Response>"
    $Valid = $false
} elseif ($Message -eq 'Start') {
    $Response = "<Response><Message>Minecraft server '$DnsRecordName.$DnsZoneName' is now starting. You will receive another message when it's ready.</Message></Response>"
} elseif ($Message -eq 'Shutdown') {
    $Response = "<Response><Message>Minecraft server '$DnsRecordName.$DnsZoneName' is now stopping. You will receive another message when it's off.</Message></Response>"
}
#endregion Process

#region Output
if ($Valid) {
    # Add request to Azure Storage Queue
    $QueueItem = @{
        Requestor = $From
        Message   = $Message
    } | ConvertTo-Json
    Push-OutputBinding -Name outputQueueItem -Value $QueueItem
}

# Log request to Azure Storage Table
Push-OutputBinding -Name outputTable -Value @{
    PartitionKey = 'default'
    RowKey       = (New-Guid).Guid
    Requestor    = $From
    Message      = $Message
}

# Send HTTP response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = 'text/html'
        Body        = $Response
    })
#endregion Output