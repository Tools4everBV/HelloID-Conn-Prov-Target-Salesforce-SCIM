#####################################################
# HelloID-Conn-Prov-Target-Salesforce-Create
#
# Version: 1.0.0.6
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    ExternalId          = $p.ExternalId
    UserName            = $p.UserName
    GivenName           = $p.Name.GivenName
    FamilyName          = $p.Name.FamilyName
    FamilyNameFormatted = $p.DisplayName
    FamilyNamePrefix    = ''
    IsUserActive        = $true
    EmailAddress        = $p.Contact.Business.Email
    EmailAddressType    = 'Work'
    IsEmailPrimary      = $true
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

function Invoke-ScimRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $InstanceUri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Endpoint,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [string]
        $TotalResults
    )

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)'"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $baseUrl = "$InstanceUri/services/scim/v2"
        $splatParams = @{
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }

        if ($Body){
            Write-Verbose 'Adding body to request'
            $splatParams['Body'] = $Body
        }

        if ($TotalResults){
            # Fixed value since each page contains 20 items max
            $count = 20
            $startIndex = 1
            [System.Collections.Generic.List[object]]$dataList = @()
            Write-Verbose 'Using pagination to retrieve results'
            do {
                $splatParams['Uri'] = "$($baseUrl)/$($Endpoint)?startIndex=$startIndex&count=$count"
                $result = Invoke-RestMethod @splatParams
                $startIndex + $count + $count
                foreach ($resource in $result.Resources){
                    $dataList.Add($resource)
                }
                $startIndex = $count+$startIndex
            } until ($dataList.Count -eq $TotalResults)
            Write-Output $dataList
        } else {
            $splatParams['Uri'] =  "$baseUrl/$Endpoint"
            Invoke-RestMethod @splatParams
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
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

try {
    #Begin
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

    Write-Verbose 'Getting total number of users'
    $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Users' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Verbose "Retrieving '$totalResults' users"
    $responseAllUsers = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Users' -Method 'GET' -headers $headers -TotalResults $totalResults

    Write-Verbose "Verifying if account for '$($p.DisplayName)' must be created or correlated"
    $lookup = $responseAllUsers | Group-Object -Property 'ExternalId' -AsHashTable
    $userObject = $lookup[$account.ExternalId]
    if ($userObject){
        Write-Verbose "Account for '$($p.DisplayName)' found with id '$($userObject.id)', switching to 'correlate'"
        $action = 'Correlate'
    } else {
        Write-Verbose "No account for '$($p.DisplayName)' has been found, switching to 'create'"
        $action = 'Create'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun){
        $auditMessage = "$action Salesforce account for: $($p.DisplayName) will be executed during enforcement"
    }

    # Process
    if (-not ($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                Write-Verbose "Creating account for '$($p.DisplayName)'"

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
                $response = Invoke-ScimRestMethod -SessionUri $sessionUri -Uri 'Users' -Method 'POST' -body $body -headers $headers
                $accountReference = $response.id
                break
            }

            'Correlate'{
                Write-Verbose "Correlating account for '$($p.DisplayName)'"
                $accountReference = $userObject.id
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action Salesforce account for: $($p.DisplayName) was successful. AccountReference is: $accountReference"
            IsError = $False
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -Error $ex
        $errorMessage = "Could not create Salesforce account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not create Salesforce account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
    }
    Write-Error $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
# End
} Finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        AuditDetails     = $auditMessage
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
