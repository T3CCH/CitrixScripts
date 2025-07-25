# Disk Space Monitor with Slack Alerts
# This script monitors cache disk free space and sends alerts to Slack when space is low
# Author: T3CCH
# v1.0
# Date: 2025-07-22

# ================================
# CONFIGURATION VARIABLES
# ================================
$SlackWebHookURL = "https://slackwebhookurlandsuch.com/blah/blah"
$DriveToMonitor = "D:"  # Drive letter to monitor (include colon)
$WarningThresholdGB = 15  # Send warning when free space drops below this (GB)
$CriticalThresholdGB = 5  # Send critical alert when free space drops below this (GB)
$TestingMode = $false # Set to $true to test alerts regardless of actual disk space
$LogFile = "C:\temp\disk_space_alerts.log"
$excludePatterns = @('FS','APP') # Modify the patterns of machine names to exclude from checking for a cache drive



# ================================
# INITIALIZE LOGGING
# ================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logEntry
    
    # Also write to console
    Write-Host $logEntry
}

# ================================
# SLACK NOTIFICATION FUNCTION
# ================================
function Send-SlackAlert {
    param(
        [string]$Message
    )
    
    try {
        $body = @{
            text = $Message
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $SlackWebHookURL -Method Post -Body $body -ContentType 'application/json'
        Write-Log "Slack alert sent successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to send Slack alert: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ================================
# DISK SPACE CHECK FUNCTION
# ================================
function Get-DiskSpaceInfo {
    param(
        [string]$DriveLetter
    )
    
    try {
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$DriveLetter'" -ErrorAction Stop
        
        if ($disk) {
            $totalSizeGB = [math]::Round($disk.Size / 1GB, 2)
            $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedSpaceGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            $freeSpacePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            
            return @{
                DriveExists = $true
                DriveLetter = $DriveLetter
                TotalSizeGB = $totalSizeGB
                FreeSpaceGB = $freeSpaceGB
                UsedSpaceGB = $usedSpaceGB
                FreeSpacePercent = $freeSpacePercent
                VolumeLabel = $disk.VolumeName
            }
        } else {
            return @{
                DriveExists = $false
                DriveLetter = $DriveLetter
            }
        }
    }
    catch {
        Write-Log "Error checking disk space for drive $DriveLetter`: $($_.Exception.Message)" "ERROR"
        return @{
            DriveExists = $false
            DriveLetter = $DriveLetter
            Error = $_.Exception.Message
        }
    }
}

# ================================
# MAIN SCRIPT EXECUTION
# ================================
Write-Log "Starting disk space monitor script" "INFO"
Write-Log "Testing Mode: $TestingMode" "INFO"
Write-Log "Drive to monitor: $DriveToMonitor" "INFO"
Write-Log "Warning threshold: $WarningThresholdGB GB" "INFO"
Write-Log "Critical threshold: $CriticalThresholdGB GB" "INFO"

# Get hostname for alerts
$hostname = $env:COMPUTERNAME
Write-Log "Hostname: $hostname" "INFO"

# Check if this computer should be excluded from D: drive monitoring

$shouldExclude = $false

foreach ($pattern in $excludePatterns) {
    if ($hostname -like "*$pattern*") {
        $shouldExclude = $true
        Write-Log "Computer hostname contains '$pattern' - skipping D: drive monitoring" "INFO"
        break
    }
}

# Exit early if computer should be excluded
if ($shouldExclude) {
    Write-Log "Script execution completed - computer excluded from D: drive monitoring" "INFO"
    Write-Log "----------------------------------------" "INFO"
    exit 0
}

# Check if drive exists and get disk space information
$diskInfo = Get-DiskSpaceInfo -DriveLetter $DriveToMonitor

# Handle case where drive doesn't exist
if (-not $diskInfo.DriveExists) {
    $errorMessage = ":rotating_light: Disk Monitor Error - $hostname`n"
    $errorMessage += ":x: Drive '$DriveToMonitor' not found or not accessible`n"
    if ($diskInfo.Error) {
        $errorMessage += "Error: $($diskInfo.Error)`n"
    }
    $errorMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    Write-Log "Drive $DriveToMonitor not found - sending error alert" "ERROR"
    Send-SlackAlert -Message $errorMessage
    exit 1
}

# Log current disk space status
Write-Log "Drive $DriveToMonitor found - Total: $($diskInfo.TotalSizeGB)GB, Free: $($diskInfo.FreeSpaceGB)GB ($($diskInfo.FreeSpacePercent)%)" "INFO"

# Determine alert level
$shouldSendAlert = $false
$alertLevel = "OK"
$alertMessage = ""

if ($TestingMode) {
    # Testing mode: Always send an alert with current status
    $shouldSendAlert = $true
    $alertLevel = "TEST"
    $alertMessage = ":white_check_mark: Disk Space Test - $hostname`n"
    Write-Log "Testing mode: Sending test alert" "INFO"
} else {
    # Normal mode: Check thresholds
    if ($diskInfo.FreeSpaceGB -le $CriticalThresholdGB) {
        $shouldSendAlert = $true
        $alertLevel = "CRITICAL"
        $alertMessage = ":rotating_light: CRITICAL Disk Space Alert - $hostname`n"
        Write-Log "Critical threshold reached: $($diskInfo.FreeSpaceGB)GB free (threshold: $CriticalThresholdGB GB)" "CRITICAL"
    } elseif ($diskInfo.FreeSpaceGB -le $WarningThresholdGB) {
        $shouldSendAlert = $true
        $alertLevel = "WARNING"
        $alertMessage = ":rotating_light: Disk Space Warning - $hostname`n"
        Write-Log "Warning threshold reached: $($diskInfo.FreeSpaceGB)GB free (threshold: $WarningThresholdGB GB)" "WARNING"
    } else {
        Write-Log "Disk space is within normal limits" "INFO"
    }
}

# Build and send alert message if needed
if ($shouldSendAlert) {
    # Add disk space details
    $alertMessage += ":file_folder: Drive: $($diskInfo.DriveLetter)"
    if ($diskInfo.VolumeLabel) {
        $alertMessage += " ($($diskInfo.VolumeLabel))"
    }
    $alertMessage += "`n"
    
    # Add space information with appropriate emoji
    if ($alertLevel -eq "CRITICAL") {
        $alertMessage += ":x: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    } elseif ($alertLevel -eq "WARNING") {
        $alertMessage += ":warning: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    } else {
        $alertMessage += ":white_check_mark: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    }
    
    $alertMessage += ":chart_with_upwards_trend: Total Size: $($diskInfo.TotalSizeGB) GB`n"
    $alertMessage += ":chart_with_downwards_trend: Used Space: $($diskInfo.UsedSpaceGB) GB`n"
    
    # Add thresholds for context (except in testing mode)
    if (-not $TestingMode) {
        $alertMessage += "`nThresholds:`n"
        $alertMessage += ":warning: Warning: $WarningThresholdGB GB`n"
        $alertMessage += ":rotating_light: Critical: $CriticalThresholdGB GB`n"
    }
    
    # Add timestamp
    $alertMessage += "`nChecked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    # Send the alert
    $alertSent = Send-SlackAlert -Message $alertMessage
    
    if (-not $alertSent) {
        Write-Log "Alert was not sent successfully" "ERROR"
    }
} else {
    Write-Log "No alert needed - disk space is within normal limits" "INFO"
}

# Log summary
Write-Log "Script execution completed. Drive: $DriveToMonitor, Free: $($diskInfo.FreeSpaceGB)GB, Alert Level: $alertLevel" "INFO"
Write-Log "----------------------------------------" "INFO"

# ================================
# MAIN SCRIPT EXECUTION
# ================================
Write-Log "Starting disk space monitor script" "INFO"
Write-Log "Testing Mode: $TestingMode" "INFO"
Write-Log "Drive to monitor: $DriveToMonitor" "INFO"
Write-Log "Warning threshold: $WarningThresholdGB GB" "INFO"
Write-Log "Critical threshold: $CriticalThresholdGB GB" "INFO"

# Get hostname for alerts
$hostname = $env:COMPUTERNAME
Write-Log "Hostname: $hostname" "INFO"

# Check if drive exists and get disk space information
$diskInfo = Get-DiskSpaceInfo -DriveLetter $DriveToMonitor

# Handle case where drive doesn't exist
if (-not $diskInfo.DriveExists) {
    $errorMessage = ":rotating_light: Disk Monitor Error - $hostname`n"
    $errorMessage += ":x: Drive '$DriveToMonitor' not found or not accessible`n"
    if ($diskInfo.Error) {
        $errorMessage += "Error: $($diskInfo.Error)`n"
    }
    $errorMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    Write-Log "Drive $DriveToMonitor not found - sending error alert" "ERROR"
    Send-SlackAlert -Message $errorMessage
    exit 1
}

# Log current disk space status
Write-Log "Drive $DriveToMonitor found - Total: $($diskInfo.TotalSizeGB)GB, Free: $($diskInfo.FreeSpaceGB)GB ($($diskInfo.FreeSpacePercent)%)" "INFO"

# Determine alert level
$shouldSendAlert = $false
$alertLevel = "OK"
$alertMessage = ""

if ($TestingMode) {
    # Testing mode: Always send an alert with current status
    $shouldSendAlert = $true
    $alertLevel = "TEST"
    $alertMessage = ":white_check_mark: Disk Space Test - $hostname`n"
    Write-Log "Testing mode: Sending test alert" "INFO"
} else {
    # Normal mode: Check thresholds
    if ($diskInfo.FreeSpaceGB -le $CriticalThresholdGB) {
        $shouldSendAlert = $true
        $alertLevel = "CRITICAL"
        $alertMessage = ":rotating_light: CRITICAL Disk Space Alert - $hostname`n"
        Write-Log "Critical threshold reached: $($diskInfo.FreeSpaceGB)GB free (threshold: $CriticalThresholdGB GB)" "CRITICAL"
    } elseif ($diskInfo.FreeSpaceGB -le $WarningThresholdGB) {
        $shouldSendAlert = $true
        $alertLevel = "WARNING"
        $alertMessage = ":rotating_light: Disk Space Warning - $hostname`n"
        Write-Log "Warning threshold reached: $($diskInfo.FreeSpaceGB)GB free (threshold: $WarningThresholdGB GB)" "WARNING"
    } else {
        Write-Log "Disk space is within normal limits" "INFO"
    }
}

# Build and send alert message if needed
if ($shouldSendAlert) {
    # Add disk space details
    $alertMessage += ":file_folder: Drive: $($diskInfo.DriveLetter)"
    if ($diskInfo.VolumeLabel) {
        $alertMessage += " ($($diskInfo.VolumeLabel))"
    }
    $alertMessage += "`n"
    
    # Add space information with appropriate emoji
    if ($alertLevel -eq "CRITICAL") {
        $alertMessage += ":x: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    } elseif ($alertLevel -eq "WARNING") {
        $alertMessage += ":warning: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    } else {
        $alertMessage += ":white_check_mark: Free Space: $($diskInfo.FreeSpaceGB) GB ($($diskInfo.FreeSpacePercent)%)`n"
    }
    
    $alertMessage += ":chart_with_upwards_trend: Total Size: $($diskInfo.TotalSizeGB) GB`n"
    $alertMessage += ":chart_with_downwards_trend: Used Space: $($diskInfo.UsedSpaceGB) GB`n"
    
    # Add thresholds for context (except in testing mode)
    if (-not $TestingMode) {
        $alertMessage += "`nThresholds:`n"
        $alertMessage += ":warning: Warning: $WarningThresholdGB GB`n"
        $alertMessage += ":rotating_light: Critical: $CriticalThresholdGB GB`n"
    }
    
    # Add timestamp
    $alertMessage += "`nChecked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    # Send the alert
    $alertSent = Send-SlackAlert -Message $alertMessage
    
    if (-not $alertSent) {
        Write-Log "Alert was not sent successfully" "ERROR"
    }
} else {
    Write-Log "No alert needed - disk space is within normal limits" "INFO"
}

# Log summary
Write-Log "Script execution completed. Drive: $DriveToMonitor, Free: $($diskInfo.FreeSpaceGB)GB, Alert Level: $alertLevel" "INFO"
Write-Log "----------------------------------------" "INFO"
