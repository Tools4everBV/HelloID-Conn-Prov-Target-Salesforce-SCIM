$config = $configuration | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-Json;

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

if(-Not($dryRun -eq $True))
{
    try {
        Write-Verbose "Setting permission account '$($aRef)' for '$($p.DisplayName)'"
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

        [System.Collections.Generic.List[object]]$entitlementList = @()
        $entitlementList.Add(
        [PSCustomObject]@{
        value   = $pRef.Reference
        }
        )

        $operations.Add(
            [PSCustomObject]@{
                op = "Replace"
                value = [PSCustomObject]@{
                    entitlements = $entitlementList
                }
            }
        )

        $body = [ordered]@{
            schemas = @(
                "urn:ietf:params:scim:api:messages:2.0:PatchOp"
            )
            Operations = $operations
        } | ConvertTo-Json -Depth 10

        Write-Verbose $body

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
                Message = "Setting permission for: $($p.DisplayName) was successful."
                IsError = $False
            })
        }
    } catch {
        $success = $false
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-HTTPError -Error $ex
            $errorMessage = "Could not set permission account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
        } else {
            $errorMessage = "Could not set permission account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
        }
        Write-Error $errorMessage
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
}

$success = $True;
$auditLogs.Add([PSCustomObject]@{
    Action = "GrantPermission";
    Message = "Permission $($pRef.Reference) added to account $($aRef)";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
    Success= $success;
    AuditLogs = $auditLogs;
    Account = [PSCustomObject]@{};
    # SubPermissions = $SubPermissions
};

Write-Output $result | ConvertTo-Json -Depth 10;
