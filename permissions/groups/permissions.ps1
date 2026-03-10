############################################################
# HelloID-Conn-Prov-Target-Salesforce-SCIM-Permissions-Group
# PowerShell V2
############################################################

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

function Invoke-ScimRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
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
        Write-Information "Invoking command '$($MyInvocation.MyCommand)'"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $baseUrl = "$InstanceUri/services/scim/v2"
        $splatParams = @{
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }

        if ($Body) {
            Write-Information 'Adding body to request'
            $splatParams['Body'] = $Body
        }

        if ($TotalResults) {
            # Fixed value since each page contains 20 items max
            $count = 20
            $startIndex = 1
            [System.Collections.Generic.List[object]]$dataList = @()
            Write-Information 'Using pagination to retrieve results'
            do {
                $splatParams['Uri'] = "$($baseUrl)/$($Endpoint)?startIndex=$startIndex&count=$count"
                $result = Invoke-RestMethod @splatParams
                $null = $startIndex + $count + $count
                foreach ($resource in $result.Resources) {
                    $dataList.Add($resource)
                }
                $startIndex = $count + $startIndex
            } until ($dataList.Count -eq $TotalResults)
            Write-Output $dataList
        }
        else {
            $splatParams['Uri'] = "$baseUrl/$Endpoint"
            Invoke-RestMethod @splatParams
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
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
#endregion

try {
    Write-Information 'Retrieving permissions'
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

    Write-Information 'Getting total number of Entitlements'
    $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Entitlements' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Information "Retrieving '$totalResults' entitlements"
    $responseAllEntitlements = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Entitlements' -Method 'GET' -headers $headers -TotalResults $totalResults

    Write-Information 'Getting total number of Roles'
    $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Roles' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Information "Retrieving '$totalResults' roles"
    $responseAllRoles = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Roles' -Method 'GET' -headers $headers -TotalResults $totalResults
    foreach ($entitlement in $responseAllEntitlements) {

        $outputContext.Permissions.Add(
            @{
                DisplayName    = $entitlement.displayName
                Identification = @{
                    Reference = $entitlement.id
                }
            }
        )
    }

    foreach ($role in $responseAllRoles) {

        $outputContext.Permissions.Add(
            @{
                DisplayName    = "Rol: " + $role.displayName
                Identification = @{
                    Reference = $role.id
                }
            }
        )
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SalesforceError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
