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

#region functions
function Get-ScimOAuthToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $ClientID,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,
        
        [Parameter(Mandatory)]
        [string]
        $UserName,
        
        [Parameter(Mandatory)]
        [string]
        $Password,

        [Parameter(Mandatory)]
        [string]
        $AuthenticationUri
    )

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)'"
        $headers = @{
            "content-type" = "application/x-www-form-urlencoded"
        }

        $splatParams = @{
            Uri     = "$($AuthenticationUri)?grant_type=password&client_id=$($ClientID)&client_secret=$($ClientSecret)&username=$($UserName)&password=$($Password)"
            Method  = 'POST'
            Headers = $Headers
        }
        Invoke-RestMethod @splatParams
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
        Write-Verbose "Disabling account '$($aRef)' for '$($p.DisplayName)'"
        Write-Verbose "Retrieving accessToken"
        $splatTokenParams = @{
            ClientID          = $($config.ClientID)
            ClientSecret      = $($config.ClientSecret)
            UserName          = $($config.UserName)
            Password          = $($config.Password)
            AuthenticationUri = $($config.AuthenticationUri)
        }
        $accessToken = Get-ScimOAuthToken @splatTokenParams
        Write-Verbose 'Adding token to authorization headers'
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $($accessToken.access_token)")
        Write-Verbose 'Getting instance url'
        $instanceUri = $($config.baseUrl)

        [System.Collections.Generic.List[object]]$operations = @()

        $operations.Add(
            [PSCustomObject]@{
                op = "Replace"
                value = @{
                    active = $false
                }
            }
        )

        $body = [ordered]@{
            schemas = @(
                "urn:ietf:params:scim:api:messages:2.0:PatchOp"
            )
            Operations = $operations
        } | ConvertTo-Json -Depth 10

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $($accessToken.access_token)")
        
        $splatParams = @{
            Uri     = "$instanceUri/services/scim/v2/Users/$aRef"
            Headers = $headers
            Body    = $body
            Method  = 'Patch'
        }
        $results = Invoke-RestMethod @splatParams
        if ($results.id){
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Disable account for: $($p.DisplayName) was successful."
                IsError = $False
            })
        }
    } catch {
        $success = $false
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-HTTPError -Error $ex
            $errorMessage = "Could not disable salesforce account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
        } else {
            $errorMessage = "Could not disable salesforce account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
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