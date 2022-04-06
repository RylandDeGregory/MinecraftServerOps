param($eventGridEvent, $TriggerMetadata)

# Make sure to pass hashtables to Out-String so they're logged correctly
$eventGridEvent | ConvertTo-Json -Depth 10 | Write-Host

$TriggerMetadata | ConvertTo-Json -Depth 10 | Write-Host

# ($eventGridEvent).Data | Out-String | Write-Host

# Log request to Azure Storage Table
# Push-OutputBinding -Name outputTable -Value @{
#     PartitionKey = 'default'
#     RowKey       = (New-Guid).Guid
#     Requestor    = $From
#     Message      = $Message
# }