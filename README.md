# HelloID-Conn-Prov-Target-SalesForce

[Work in progress]

<p align="center">
  <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/Salesforce.com_logo.svg/1200px-Salesforce.com_logo.svg.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Supported PowerShell versions](#Supported-PowerShell-versions)
- [Setup the connector](#Setup-the-connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-Docs)

## Introduction

The _HelloID-Conn-Prov-Target-SalesForce_ connector creates/updates user accounts in SalesForce. The SalesForce API is a scim (http://www.simplecloud.info) API. The code used for this connector is based upon the _https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Generic-Scim_ generic scim connector.

## Getting started

### Connection settings

| Setting     | Description |
| ------------ | ----------- |
| ClientID          | The ClientID for the SCIM API                      |
| ClientSecret      | The ClientSecret for the SCIM API                  |
| Uri               | The Uri to the SCIM API. <http://some-api/v1/scim> |

### Prerequisites

- When using the HelloID On-Premises agent, Windows PowerShell 5.1 must be installed.

- When the connector needs to be modified, make sure to have installed VSCode/PowerShell extension.

### Supported PowerShell versions

The connector is created for both Windows PowerShell 5.1 and PowerShell Core 7.0.3. This means that the connector can be executed in both cloud and on-premises using the HelloID Agent.

> Older versions of Windows PowerShell are not supported.

## Setup the connector

1. Make sure you have access to the scim based API for your application.

2. Add a new 'Target System' to HelloID.

3. On the _Account_ tab, click __Custom connector configuration__ and import the code from the _configuration.json_ file.

4. Under __Account Create__ click __Configure__ and import the code from the _create.ps1_ file.

5. Repeat step (4) for the other *.ps1 files.

7. Go to the _Configuration_ tab and fill in the required fields.

| Parameter         | Description                                        |
| ----------------- | -------------------------------------------------- |
| ClientID          | The ClientID for the SCIM API                      |
| ClientSecret      | The ClientSecret for the SCIM API                  |
| Uri               | The Uri to the SCIM API. <http://some-api/v1/scim> |
| IsConnectionTls12 | Enables TLS 1.2 (Only necessary when using Windows PowerShell 5.1)        |

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID Docs

The official HelloID documentation can be found at: https://docs.helloid.com/
