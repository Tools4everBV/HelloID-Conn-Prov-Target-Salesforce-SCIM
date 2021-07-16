#####################################################
# HelloID-Conn-Prov-Target-SalesForce-Create
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$personObj = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    ExternalId          = $personObj.ExternalId
    UserName            = $personObj.UserName
    GivenName           = $personObj.Name.GivenName
    FamilyName          = $personObj.Name.FamilyName
    FamilyNameFormatted = $personObj.DisplayName
    FamilyNamePrefix    = ''
    IsUserActive        = $true
    EmailAddress        = $personObj.Contact.Business.Email
    EmailAddressType    = 'Work'
    IsEmailPrimary      = $true
}

#region Helper Functions
function Get-GenericScimOAuthToken {
    <#
    .SYNOPSIS
    Retrieves the OAuth token from a SCIM API <http://www.simplecloud.info/>

    .PARAMETER ClientID
    The ClientID for the SCIM API

    .PARAMETER ClientSecret
    The ClientSecret for the SCIM API
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ClientID,

        [Parameter(Mandatory = $true)]
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

        $splatRestMethodParameters = @{
            Uri     = 'https://login.salesforce.com/services/oauth2/token'
            Method  = 'POST'
            Headers = $headers
            Body    = $body
        }
        Invoke-RestMethod @splatRestMethodParameters
        Write-Verbose 'Finished retrieving accessToken'
    }
    catch {
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
        Write-Verbose "Creating account for '$($personObj.DisplayName)'"
        Write-Verbose 'Retrieving accessToken'
        $accessToken = Get-GenericScimOAuthToken -ClientID $($config.ClientID) -ClientSecret $($config.ClientSecret)

        [System.Collections.Generic.List[object]]$emailList = @()
        $emailList.Add(
            [PSCustomObject]@{
                primary = $account.IsEmailPrimary
                type    = $account.EmailAddressType
                display = $account.EmailAddress
                value   = $account.EmailAddress
            }
        )

        $body = [ordered]@{
            schemas    = @(
                "urn:ietf:params:scim:schemas:core:2.0:User",
                "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
            )
            externalId = $account.ExternalID
            userName   = $account.UserName
            active     = $account.IsUserActive
            emails     = $emailList
            meta       = @{
                resourceType = "User"
            }
            name = [ordered]@{
                formatted        = $account.NameFormatted
                familyName       = $account.FamilyName
                familyNamePrefix = $account.FamilyNamePrefix
                givenName        = $account.GivenName
            }
        } | ConvertTo-Json

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $accessToken")
        $splatParams = @{
            Uri      = "$($config.BaseUrl)/services/scim/v2/Users"
            Headers  = $headers
            Body     = $body
            Method   = 'Post'
        }

        $results = Invoke-RestMethod @splatParams
        if ($results.id){
            $logMessage = "Account for '$($personObj.DisplayName)' successfully created with id: '$($results.id)'"
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
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $errorMessage"
        } else {
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $($ex.Exception.Message)"
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
    AccountReference = $($results.id)
    AuditLogs        = $auditLogs
}

Write-Output $result | ConvertTo-Json -Depth 10