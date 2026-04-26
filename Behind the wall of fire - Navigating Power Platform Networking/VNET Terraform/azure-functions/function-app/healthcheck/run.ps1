using namespace System.Net

param($Request, $TriggerMetadata)

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = @{ status = "healthy"; timestamp = (Get-Date -Format o) } | ConvertTo-Json
})
