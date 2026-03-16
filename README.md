# HelloID-Conn-Prov-Target-Salesforce-SCIM

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!WARNING]
This connector has been updated to meet the requirements of a PowerShell V2 target connector.<br>
The update was dry-coded and could not be tested in a working environment.<br>
We recommend thoroughly testing and validating the connector during implementation, as the code may require adjustments.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="./Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Salesforce-SCIM](#helloid-conn-prov-target-salesforce-scim)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Salesforce-SCIM_ is a _target_ connector. _Salesforce-SCIM_ provides a set of REST APIs that allow you to programmatically interact with its data. The SalesForce API is a scim based (http://www.simplecloud.info) API. The code used for this connector is based on the _https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Generic-Scim_ generic scim connector.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 | Static  |
| **Resources**                             | ❌         | -                                       |         |
| **Entitlement Import: Accounts**          | ✅         | -                                       |         |
| **Entitlement Import: Permissions**       | ❌         | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |         |

<!--
Example
### ⚠️ Governance Reconciliation Resolutions
Governance reconciliation is supported for reporting purposes.
Resolutions are not possible because...
-->

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Salesforce-SCIM/refs/heads/main/Icon.png
```

### Requirements

<!--
Describe the specific requirements that must be met before using this connector, such as the need for an agent, a certificate or IP whitelisting.

**Please ensure to list the requirements using bullet points for clarity.**

Example:

- **SSL Certificate**:<br>
  A valid SSL certificate must be installed on the server to ensure secure communication. The certificate should be trusted by a recognized Certificate Authority (CA) and must not be self-signed.
- **IP Whitelisting**:<br>
  The IP addresses used by the connector must be whitelisted on the target system's firewall to allow access. Ensure that the firewall rules are configured to permit incoming and outgoing connections from these IPs.
-->

### Connection settings

The following settings are required to connect to the API.

| Setting           | Description                                                                                  | Mandatory |
| ----------------- | -------------------------------------------------------------------------------------------- | --------- |
| ClientID          | The ClientID to the Salesforce SCIM API                                                      | Yes       |
| ClientSecret      | The ClientSecret to the Salesforce SCIM API                                                  | Yes       |
| UserName          | The UserName to the Salesforce SCIM API                                                      | Yes       |
| Password          | The Password to the Salesforce SCIM API                                                      | Yes       |
| BaseUrl           | The BaseUrl to the Salesforce environment. e.g. [https://customer.my.salesforce.com]         | Yes       |
| AuthenticationUri | The URI to retrieve the oAuth token. e.g [https://test.salesforce.com/services/oauth2/token] | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Salesforce-SCIM_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employeeNumber`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _Salesforce-SCIM_

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint      | HTTP Method | Description                                  |
| ------------- | ----------- | -------------------------------------------- |
| /Users        | GET         | Create, update and retrieve user information |
| /Entitlements | GET         | Retrieve entitlements                        |
| /Roles        | GET         | Retrieve roles                               |

### API documentation

https://help.salesforce.com/s/articleView?id=xcloud.identity_overview.htm&type=5

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
