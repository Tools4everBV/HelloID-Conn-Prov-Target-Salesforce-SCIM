#################################################
# HelloID-Conn-Prov-Target-Salesforce-SCIM-Update
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
        [object]
        $AccountObject
    )
    process {

        # Making sure only fieldMapping fields are imported
        $helloidAccountObject = [PSCustomObject]@{}
        foreach ($property in $actionContext.Data.PSObject.Properties) {
            switch ($property.Name) {
                'employeeNumber' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.employeeNumber }
                'userName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.userName }
                'givenName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.givenName }
                'familyName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyName }
                'familyNameFormatted' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyNameFormatted }
                'familyNamePrefix' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyNamePrefix }
                'department' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.department }
                'mobilePhone' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.phoneNumbers.value }
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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

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

    Write-Information 'Verifying if a Salesforce-SCIM account exists'
    try {
        $splatGetUserParams = @{
            Uri     = "$instanceUri/services/scim/v2/Users/$($actionContext.References.Account)"
            Headers = $headers
            Body    = $body
            Method  = 'GET'
        }
        $responseAccount = Invoke-RestMethod @splatGetUserParams
        $correlatedAccount = ConvertTo-HelloIDAccountObject -AccountObject $responseAccount
        $outputContext.PreviousData = $correlatedAccount

    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            $correlatedAccount = $null
        }
        else {
            throw $_
        }
    }

    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
        }
        else {
            $action = 'NoChanges'
        }
    }
    else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Salesforce-SCIM account with accountReference: [$($actionContext.References.Account)]"
                [System.Collections.Generic.List[object]]$operations = @()
                foreach ($property in $propertiesChanged) {
                    switch ($property.Name) {
                        'department' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'department'
                                    value = $property.Value
                                }
                            )
                        }
                        'emailAddress' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'emails.value'
                                    value = $property.Value
                                }
                            )
                        }
                        'emailAddressType' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'emails.type'
                                    value = $property.Value
                                }
                            )
                        }
                        'employeeNumber' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'employeeNumber'
                                    value = $property.Value
                                }
                            )
                        }
                        'familyName' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'name.familyName'
                                    value = $property.Value
                                }
                            )
                        }
                        'familyNamePrefix' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'name.familyNamePrefix'
                                    value = $property.Value
                                }
                            )
                        }
                        'familyNameFormatted' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'name.formatted'
                                    value = $property.Value
                                }
                            )
                        }
                        'givenName' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'name.givenName'
                                    value = $property.Value
                                }
                            )
                        }
                        'mobilePhone' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'phoneNumbers.value'
                                    value = $property.Value
                                }
                            )
                        }
                        'userName' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'userName'
                                    value = $property.Value
                                }
                            )
                        }
                    }
                }

                $body = [ordered]@{
                    schemas    = @(
                        'urn:ietf:params:scim:api:messages:2.0:PatchOp'
                    )
                    Operations = $operations
                } | ConvertTo-Json

                $splatUpdateUser = @{
                    Uri         = "$instanceUri/services/scim/v2/Users/$($actionContext.References.Account)"
                    Headers     = $headers
                    Body        = $body
                    Method      = 'PATCH'
                    ContentType = 'application/json'
                }
                $null = Invoke-RestMethod @splatUpdateUser
            }
            else {
                Write-Information "[DryRun] Update Salesforce-SCIM account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Salesforce-SCIM account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating Salesforce-SCIM account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Salesforce-SCIM account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Salesforce-SCIM account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SalesforceError -ErrorObject $ex
        $auditLogMessage = "Could not update Salesforce-SCIM account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update Salesforce-SCIM account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
