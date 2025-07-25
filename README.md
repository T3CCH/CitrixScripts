# Citrix PowerShell Scripts with Slack alerting

A collection of PowerShell scripts I use for Citrix environments. Currently includes two utilities focused on service health and cache disk monitoring.

## Scripts

### 1. `ServiceChecker.ps1`

This script monitors the status of specified Windows services on a Citrix server. It:

- Checks the configured services
- Sends a report to a configured Slack webhook.
- Restarts any services that are listed as needing a restart.
- Checks service names to be listed in a configurable variable again
- Attempts the number of attempts in the script.
- Reports the outcome
- Gives up after the number of trys has expired and requires manual intervention
- Change the test mode variable to true verify if you have the script running correctly. 

> ⚠️ You **must** update the Slack webhook URL and configure the required service variables before use.

### 2. `cachediskcheck.ps1`

Checks the usage of an MCS cache disk to help determine if it needs to be resized. It:

- Evaluates cache disk usage.
- Compares it against configurable warning and critical thresholds.
- Sends usage alerts to a configured Slack webhook.
- If the alerts are
- Set as a scheduled task
- Change the test mode variable to true verify if you have the script running correctly. 

> ⚠️ You **must** update the Slack webhook URL and configure the required service variables before use.

## Configuration

For both scripts:

- Open the `.ps1` file in a text editor.
- Update the Slack webhook URL.
- Configure the required variables near the top of each script.


**Example Usage via Scheduled Task:**
- The lines that are executed are below. So you will configure your app 'powershell.exe' with arguments following in the arguments section of the scheduled task.

```powershell
powershell.exe -executionpolicy bypass -command "C:\Path\To\ServiceChecker.ps1"

```
```powershell 
powershell.exe -executionpolicy bypass -command "\\domain.whatever\sysvol\scripts\ServiceChecker.ps1"
```

