# Citrix PowerShell Scripts

A collection of PowerShell scripts I use for Citrix environments. Currently includes two utilities focused on service health and cache disk monitoring.

## Scripts

### 1. `ServiceChecker.ps1`

This script monitors the status of specified Windows services on a Citrix server. It:

- Sends a report to a configured Slack webhook.
- Restarts any services that are listed as needing a restart.
- Allows service names to be listed in a configurable variable.

> ⚠️ You **must** update the Slack webhook URL and configure the required service variables before use.

### 2. `cachediskcheck.ps1`

Checks the usage of an MCS cache disk to help determine if it needs to be resized. It:

- Evaluates cache disk usage.
- Compares it against configurable warning and critical thresholds.
- Sends usage alerts to a configured Slack webhook.

> ⚠️ You **must** update the Slack webhook URL and configure threshold variables before use.

## Configuration

For both scripts:

- Open the `.ps1` file in a text editor.
- Update the Slack webhook URL.
- Configure the required variables near the top of each script.
