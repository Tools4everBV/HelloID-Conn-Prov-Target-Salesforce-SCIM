#################################################
# HelloID-Conn-Prov-Target-Salesforce-SCIM-Create
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

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    process {

        # Making sure only fieldMapping fields are imported
        $helloidAccountObject = [PSCustomObject]@{}
        foreach ($property in $actionContext.Data.PSObject.Properties) {
            switch ($property.Name) {
                'employeeNumber      ' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.employeeNumber }
                'userName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.userName }
                'givenName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.givenName }
                'familyName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyName }
                'familyNameFormatted ' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyNameFormatted }
                'familyNamePrefix' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyNamePrefix }
                'department' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.department }
                'mobilePhone ' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.phoneNumbers.value }
                'mobilePhoneType' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.phoneNumbers.type }
                'active' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.active }
                'emailAddress' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.emailAddress }
                'isEmailPrimary' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue "$($AccountObject.isEmailPrimary)" }
                'emailAddressType' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.emailAddressType }
                'emailEncodingKey' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.emailEncodingKey }
                'userType' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.userType }
                'id' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.id }
            }
        }
        Write-Output $helloidAccountObject
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

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
    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($accessToken.access_token)")

    Write-Information 'Getting instance url'
    $instanceUri = $($actionContext.Configuration.BaseUrl)

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Salesforce account exists where $correlationField is: [$correlationValue]"
        $response = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint "Users?filter=$orrelationField eq ""$($correlationValue)""" -Method 'GET' -headers $headers
        $correlatedAccount = $response.Resources
    }

    if ($correlatedAccount.Count -eq 0) {
        $action = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $action = 'CorrelateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Salesforce account'
                $primaryEmailTrue = [System.Convert]::ToBoolean($actionContext.Data.isEmailPrimary)
                [System.Collections.Generic.List[object]]$emailList = @()
                $emailList.Add(
                    [PSCustomObject]@{
                        primary = $primaryEmailTrue
                        type    = $actionContext.Data.emailAddressType
                        display = $actionContext.Data.emailAddress
                        value   = $actionContext.Data.emailAddress
                    }
                )

                [System.Collections.Generic.List[object]]$entitlementList = @()
                $entitlementList.Add(
                    [PSCustomObject]@{
                        value   = $account.Entitlement
                    }
                )

                [System.Collections.Generic.List[object]]$phoneList = @()
                $phoneList.Add(
                    [PSCustomObject]@{
                        type  = $actionContext.Data.mobilePhoneType
                        value = $actionContext.Data.mobilePhone
                    }
                )

                $body = [ordered]@{
                    schemas          = @(
                        "urn:ietf:params:scim:schemas:core:2.0:User",
                        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
                    )
                    employeeNumber   = $actionContext.Data.employeeNumber
                    userName         = $actionContext.Data.userName
                    emails           = $emailList
                    emailEncodingKey = $actionContext.Data.emailEncodingKey
                    department       = $actionContext.Data.department
                    userType         = $actionContext.Data.userType
                    phoneNumbers     = $phoneList
                    meta             = @{
                        resourceType = "User"
                    }
                    name             = [ordered]@{
                        formatted        = $actionContext.Data.familyNameFormatted
                        familyName       = $actionContext.Data.familyName
                        familyNamePrefix = $actionContext.Data.familyNamePrefix
                        givenName        = $actionContext.Data.givenName
                    }
                    entitlements = $entitlementList
                    active = $false
                } | ConvertTo-Json
                $createdAccount = Invoke-ScimRestMethod -InstanceUri $instanceUri -Endpoint 'Users' -Method 'POST' -body $body -headers $headers
                $outputContext.Data = ConvertTo-HelloIDAccountObject($createdAccount)
                $outputContext.AccountReference = $createdAccount.id
            }
            else {
                Write-Information '[DryRun] Create and correlate Salesforce account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Salesforce account'
            $outputContext.Data = ConvertTo-HelloIDAccountObject($correlatedAccount)
            $outputContext.AccountReference = $correlatedAccount.id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SalesforceError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate Salesforce account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Salesforce account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}