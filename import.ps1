#################################################
# HelloID-Conn-Prov-Target-Salesforce-SCIM-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
        Write-Information "Invoking command '$($MyInvocation.MyCommand)'"
        $headers = @{
            "content-type" = "application/x-www-form-urlencoded"
        }

        $splatParams = @{
            Uri     = "$($AuthenticationUri)?grant_type=password&client_id=$($ClientID)&client_secret=$($ClientSecret)&username=$($UserName)&password=$($Password)"
            Method  = 'POST'
            Headers = $Headers
        }
        Invoke-RestMethod @splatParams
        Write-Information 'Finished retrieving accessToken'
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}

function Resolve-SalesforceError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.detail
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$AccountObject
    )

    [PSCustomObject]@{
        employeeNumber     = $AccountObject.employeeNumber
        userName           = $AccountObject.userName
        givenName          = $AccountObject.name.givenName
        familyName         = $AccountObject.name.familyName
        familyNameFormatted= $AccountObject.name.familyNameFormatted
        familyNamePrefix   = $AccountObject.name.familyNamePrefix
        department         = $AccountObject.department
        mobilePhone        = $AccountObject.phoneNumbers.value
        mobilePhoneType    = $AccountObject.phoneNumbers.type
        active             = $AccountObject.active
        emailAddress       = $AccountObject.emailAddress
        isEmailPrimary     = [string]$AccountObject.isEmailPrimary
        emailAddressType   = $AccountObject.emailAddressType
        emailEncodingKey   = $AccountObject.emailEncodingKey
        userType           = $AccountObject.userType
        id                 = $AccountObject.id
    }
}
#endregion

try {
    Write-Information 'Starting Salesforce-SCIM account entitlement import'
    Write-Information 'Retrieving accessToken'
    $splatTokenParams = @{
        ClientID          = $($actionContext.Configuration.ClientID)
        ClientSecret      = $($actionContext.Configuration.ClientSecret)
        UserName          = $($actionContext.Configuration.UserName)
        Password          = $($actionContext.Configuration.Password)
        AuthenticationUri = $($actionContext.Configuration.AuthenticationUri)
    }
    $accessToken = Get-ScimOAuthToken @splatTokenParams

    Write-Information 'Adding token to authorization headers'
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($accessToken.access_token)")

    Write-Information 'Getting instance url'
    $instanceUri = $($actionContext.Configuration.BaseUrl)

    $take = 20
    $startIndex = 0
    do {
        $splatImportAccountParams = @{
            Uri     = "$instanceUri/services/scim/v2/Users?startIndex=$($startIndex)&count=$($take)"
            Method  = 'GET'
            Headers = $headers
        }

        $response = Invoke-RestMethod @splatImportAccountParams

        $result = $response.Resources
        $totalResults = $response.totalResults

        if ($null -ne $result) {
            foreach ($importedAccount in $result) {
                $data = ConvertTo-HelloIDAccountObject -AccountObject $importedAccount

                # Set Enabled based on importedAccount status
                $isEnabled = $false
                if ($importedAccount.active -eq $true) {
                    $isEnabled = $true
                }

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.name.formatted)"
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.id
                }

                # Make sure the userName has a value
                $UserName = $importedAccount.UserName
                if ([string]::IsNullOrWhiteSpace($UserName)) {
                    $UserName = $importedAccount.id
                }

                Write-Output @{
                    AccountReference = $importedAccount.id
                    displayName      = $displayName
                    UserName         = $UserName
                    Enabled          = $isEnabled
                    Data             = $data
                }
                $startIndex++
            }
        }
    } while (($result.count -gt 0) -and ($startIndex -lt $totalResults))
    Write-Information 'Salesforce-SCIM account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SalesforceError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Salesforce-SCIM account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Salesforce-SCIM account entitlements. Error: $($ex.Exception.Message)"
    }
}