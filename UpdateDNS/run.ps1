param($eventGridEvent, $TriggerMetadata)

# Make sure to pass hashtables to Out-String so they're logged correctly
$eventGridEvent | Out-String | Write-Host

# Log request to Azure Storage Table
# Push-OutputBinding -Name outputTable -Value @{
#     PartitionKey = 'default'
#     RowKey       = (New-Guid).Guid
#     Requestor    = $From
#     Message      = $Message
# }