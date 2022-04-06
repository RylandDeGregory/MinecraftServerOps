param($eventGridEvent, $TriggerMetadata)

$TriggerMetadata.Data.Claims.Name

# ($eventGridEvent).Data | Out-String | Write-Host

# Log request to Azure Storage Table
# Push-OutputBinding -Name outputTable -Value @{
#     PartitionKey = 'default'
#     RowKey       = (New-Guid).Guid
#     Requestor    = $From
#     Message      = $Message
# }