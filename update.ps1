#####################################################
# HelloID-Conn-Prov-Target-Salesforce-Update
#
# Version: 1.0.0.3
#####################################################
$VerbosePreference = 'Continue'

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    GivenName           = $pd.Name.GivenName.New
    FamilyName          = $pd.Name.FamilyName.New
    FamilyNameFormatted = $pd.DisplayName.New
    FamilyNamePrefix    = $pd.DisplayName.FamilyNamePrefix.New
    IsUserActive        = $true
    Department          = $pd.PrimaryContract.Department.DisplayName.New
}

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
        Write-Verbose "Updating account '$($aRef)' for '$($p.DisplayName)'"
        Write-Verbose 'Retrieving accessToken'
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

        if ($account.FamilyName){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    value = @{
                        name = @{
                            formatted        = $account.FamilyNameFormatted
                            familyName       = $account.FamilyName
                            familyNamePrefix = $account.FamilyNamePrefix
                            givenName        = $account.GivenName
                        }
                  }
         }
              ) 
       }

        if ($account.Department){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    value = @{
                        department = $account.Department
                    }
                }
            )
        }

        $body = [ordered]@{
            schemas = @(
                "urn:ietf:params:scim:api:messages:2.0:PatchOp"
            )
            Operations = $operations
        } | ConvertTo-Json -Depth 10
        
        $splatParams = @{
            Uri     = "$instanceUri/services/scim/v2/Users/$aRef"
            Headers = $headers
            Body    = $body
            Method  = 'Patch'
        }

        write-verbose $operations.count

        If($operations.count -gt 0){
        $results = Invoke-RestMethod @splatParams
        if ($results.id){
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Update account for: $($p.DisplayName) was successful."
                IsError = $False
            })
        }
        } $success = $true
    } catch {
        $success = $false
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-HTTPError -Error $ex
            $errorMessage = "Could not update salesforce account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
        } else {
            $errorMessage = "Could not update salesforce account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
        }
        Write-Error $errorMessage
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } finally {
        $result = [PSCustomObject]@{
            Success          = $success
            Account          = $account
            AuditDetails     = $auditMessage
        }
        Write-Output $result | ConvertTo-Json -Depth 10
    }
}