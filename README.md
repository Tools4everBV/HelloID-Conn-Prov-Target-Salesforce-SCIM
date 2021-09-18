# HelloID-Conn-Prov-Target-SalesForce-SCIM

<p align="center">
  <img src="./assets/logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Supported PowerShell versions](#Supported-PowerShell-versions)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-Docs)

## Introduction

The _HelloID-Conn-Prov-Target-SalesForce_ connector creates/updates user accounts in SalesForce. The SalesForce API is a scim (http://www.simplecloud.info) API. The code used for this connector is based on the _https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Generic-Scim_ generic scim connector.

> Note that this connector has not been tested on a SalesForce implementation. Changes might have to be made to the code according to your requirements

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting     | Description |
| ------------ | ----------- |
| ClientID | The ClientID for the SCIM API |
| ClientSecret | The ClientSecret for the SCIM API |
| BaseUrl | The Uri to the SCIM API. <http://<your-application> |

### Prerequisites

- When using the HelloID On-Premises agent, Windows PowerShell 5.1 must be installed.

### Supported PowerShell versions

The connector is created for both Windows PowerShell 5.1 and PowerShell Core. This means that the connector can be executed in both cloud and on-premises using the HelloID Agent.

> Older versions of Windows PowerShell are not supported.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012518799-How-to-add-a-target-system)

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)

## HelloID Docs

The official HelloID documentation can be found at: https://docs.helloid.com/
