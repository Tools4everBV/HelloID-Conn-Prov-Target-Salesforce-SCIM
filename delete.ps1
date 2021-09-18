#####################################################
# HelloID-Conn-Prov-Target-Salesforce-Delete
#
# Version: 1.0.0.2
#####################################################
$VerbosePreference = 'Continue'

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

#region Helper Functions
function Get-ScimOAuthToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $ClientID,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret
    )

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)'"
        $headers = @{
            "content-type" = "application/x-www-form-urlencoded"
        }

        $body = @{
            client_id     = $ClientID
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }

        Invoke-RestMethod -Uri 'https://login.salesforce.com/services/oauth2/token' -Method 'POST' -Body $body -Headers $headers
        Write-Verbose 'Finished retrieving accessToken'
    } catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj.ErrorMessage = $errorResponse
        }
        Write-Output $HttpErrorObj
    }
}
#endregion

if (-not($dryRun -eq $true)) {
    try {
        Write-Verbose "Deleting account '$($aRef)' for '$($p.DisplayName)'"
        Write-Verbose "Retrieving accessToken"
        $accessToken = Get-ScimOAuthToken -ClientID $($config.ClientID) -ClientSecret $($config.ClientSecret)

        [System.Collections.Generic.List[object]]$operations = @()

        $operations.Add(
            [PSCustomObject]@{
                op = "Replace"
                path = "active"
                value = $false
            }
        )

        $body = [ordered]@{
            schemas = @(
                "urn:ietf:params:scim:api:messages:2.0:PatchOp"
            )
            Operations = $operations
        } | ConvertTo-Json

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $accessToken")
        $splatParams = @{
            Uri     = "$($config.BaseUrl)/services/scim/v2/Users/$aRef"
            Headers = $headers
            Body    = $body
            Method  = 'Patch'
        }
        $results = Invoke-RestMethod @splatParams
        if ($results.id){
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Delete account for: $($p.DisplayName) was successful."
                IsError = $False
            })
        }
    } catch {
        $success = $false
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-HTTPError -Error $ex
            $errorMessage = "Could not delete salesforce account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
        } else {
            $errorMessage = "Could not delete salesforce account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
        }
        Write-Error $errorMessage
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } finally {
        $result = [PSCustomObject]@{
            Success          = $success
            AuditDetails     = $auditMessage
        }
        Write-Output $result | ConvertTo-Json -Depth 10
    }
}
