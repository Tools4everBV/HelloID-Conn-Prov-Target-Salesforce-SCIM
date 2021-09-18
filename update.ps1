#####################################################
# HelloID-Conn-Prov-Target-SalesForce-Update
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = 'Continue'

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$personObj = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    ExternalId          = $pd.ExternalId.New
    UserName            = $pd.UserName.New
    GivenName           = $pd.Name.GivenName.New
    FamilyName          = $pd.Name.FamilyName.New
    FamilyNameFormatted = $pd.DisplayName.New
    FamilyNamePrefix    = $pd.DisplayName.FamilyNamePrefix.New
    IsUserActive        = $true
    EmailAddress        = $pd.Contact.Business.Email.New
    IsEmailPrimary      = $true
}

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
        $HttpErrorObj = @{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj['ErrorMessage'] = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj['ErrorMessage'] = $errorResponse
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.RequestUri), InvocationCommand: '$($HttpErrorObj.MyCommand)"
    }
}
#endregion

if (-not($dryRun -eq $true)) {
    try {
        Write-Verbose "Updating account '$($aRef)' for '$($personObj.DisplayName)'"
        Write-Verbose 'Retrieving accessToken'
        $accessToken = Get-ScimOAuthToken -ClientID $($config.ClientID) -ClientSecret $($config.ClientSecret)

        [System.Collections.Generic.List[object]]$operations = @()

        if ($account.ExternalId){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    path = "externalId"
                    value = $account.ExternalId
                }
            )
        }

        if ($account.UserName){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    path = "userName"
                    value = $account.UserName
                }
            )
        }

        if ($account.GivenName){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    path = "name.givenName"
                    value = $account.GivenName
                }
            )
        }

        if ($account.FamilyName){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    path = "name.familyName"
                    value = $account.FamilyName
                }
            )
        }

        if ($account.EmailAddress){
            $operations.Add(
                [PSCustomObject]@{
                    op = "Replace"
                    path = 'emails[type eq "work"].value'
                    value = $account.EmailAddress
                }
            )
        }

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
            $logMessage = "Account '$($aRef) for '$($personObj.DisplayName)' successfully updated"
            Write-Verbose $logMessage
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = $logMessage
                IsError = $False
            })
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account '$($aRef)' for '$($personObj.DisplayName)' not updated. Error: $errorMessage"
        } else {
            $auditMessage = "Account '$($aRef)' for '$($personObj.DisplayName)' not updated. Error: $($ex.Exception.Message)"
        }
        $auditLogs.Add([PSCustomObject]@{
                Message = $auditMessage
                IsError = $true
            })
        Write-Error $auditMessage
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AuditDetails     = $auditMessage
}

Write-Output $result | ConvertTo-Json -Depth 10
