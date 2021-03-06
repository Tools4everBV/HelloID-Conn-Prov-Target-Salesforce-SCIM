#####################################################
# HelloID-Conn-Prov-Target-Salesforce-Permissions
#
# Version: 1.0.0.6
#####################################################
$VerbosePreference = "Continue"
$config = $configuration | ConvertFrom-Json

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
                $null = $startIndex + $count + $count
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

    Write-Verbose 'Getting total number of Entitlements'
    $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Entitlements' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Verbose "Retrieving '$totalResults' entitlements"
    $responseAllEntitlements = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Entitlements' -Method 'GET' -headers $headers -TotalResults $totalResults

    Write-Verbose 'Getting total number of Roles'
    $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Roles' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Verbose "Retrieving '$totalResults' roles"
    $responseAllRoles = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Roles' -Method 'GET' -headers $headers -TotalResults $totalResults

    $permissions = New-Object System.Collections.Generic.List[System.Object]

    foreach ($entitlement in $responseAllEntitlements) {
        $permission = [PSCustomObject]@{
            DisplayName    = $entitlement.displayName
            Identification = @{
                Reference = $entitlement.id;
            }
        } 
        $permissions.Add($permission)
    }

    foreach ($role in $responseAllRoles) {
        $permission = [PSCustomObject]@{
            DisplayName    = "Rol: " + $role.displayName
            Identification = @{
                Reference = $role.id;
            }
        } 
        $permissions.Add($permission)
    }

    $success = $true   
}
catch {
    $success = $false
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -Error $ex
        $errorMessage = "Could not receive Salesforce entitlements, roles. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not receive Salesforce entitlements, roles. Error: $($ex.Exception.Message)"
    }
    Write-Error $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    # End
}
Finally {
    Write-Output $permissions | ConvertTo-Json -Depth 10;
}