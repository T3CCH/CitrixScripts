# Service Monitor with Slack Alerts and Auto-Restart
# This script monitors Windows services and sends alerts to Slack when services are down
# Optionally auto-restarts specified services with failure tracking
# Author: T3CCH
# Date: 2025-07-22

# ================================
# CONFIGURATION VARIABLES
# ================================
$SlackWebHookURL = "https://slackwebhookurlandsuch.com/blah/blah"
$ServicesConfig = "CpSvc,Spooler,BrokerAgent"  # Comma-separated list of Windows service names to monitor
$TestingMode = $false  # Set to $true to test alerts without attempting service restarts
$excludePatterns = @('FS', 'APP')  # Skip monitoring for hostnames containing these patterns
$ServicesToRestart = @('CpSvc')  # Services that will be auto-restarted if down
                         # NOTE: Service must be in BOTH $ServicesConfig AND $ServicesToRestart to be auto-restarted
                         # Example: @('CpSvc') will only auto-restart CpSvc, allowing manual handling of other services
$RestartWaitTimeSeconds = 30  # Time to wait after restart attempt before re-checking status
$MaxRestartAttempts = 3  # Maximum retry attempts before giving up on a service. It checks once per schedule task run.
$FailureResetMinutes = 59  # Reset failure tracking after this many minutes (1440 = 24 hours, 60 = 1 hour) might make sense to have an odd numbered time. 
$LogFile = "C:\temp\slack_alerts.log"

# ================================
# INITIALIZE PATHS AND LOGGING
# ================================
# Calculate failure tracking path from log directory
$LogDir = Split-Path $LogFile -Parent
$FailureTrackingPath = Join-Path $LogDir "service_failures"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    # Ensure failure tracking directory exists
    if (-not (Test-Path $FailureTrackingPath)) {
        New-Item -ItemType Directory -Path $FailureTrackingPath -Force | Out-Null
        Write-Host "[$timestamp] [INFO] Created failure tracking directory: $FailureTrackingPath"
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
# FAILURE TRACKING FUNCTIONS
# ================================
function Get-FailureTracking {
    param([string]$ServiceName)
    
    $failureFile = Join-Path $FailureTrackingPath "$ServiceName`_failed.txt"
    
    if (Test-Path $failureFile) {
        try {
            $content = Get-Content $failureFile -Raw
            $parts = $content.Split('|')
            if ($parts.Count -eq 2) {
                return @{
                    AttemptCount = [int]$parts[0]
                    LastAttempt = [datetime]$parts[1]
                    FilePath = $failureFile
                }
            }
        }
        catch {
            Write-Log "Error reading failure file for $ServiceName`: $($_.Exception.Message)" "ERROR"
        }
    }
    
    return $null
}

function Set-FailureTracking {
    param(
        [string]$ServiceName,
        [int]$AttemptCount
    )
    
    $failureFile = Join-Path $FailureTrackingPath "$ServiceName`_failed.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = "$AttemptCount|$timestamp"
    
    try {
        Set-Content -Path $failureFile -Value $content
        Write-Log "Updated failure tracking for $ServiceName`: Attempt $AttemptCount" "INFO"
    }
    catch {
        Write-Log "Error writing failure file for $ServiceName`: $($_.Exception.Message)" "ERROR"
    }
}

function Remove-FailureTracking {
    param([string]$ServiceName)
    
    $failureFile = Join-Path $FailureTrackingPath "$ServiceName`_failed.txt"
    
    if (Test-Path $failureFile) {
        try {
            Remove-Item $failureFile -Force
            Write-Log "Removed failure tracking for $ServiceName (service successfully restarted)" "INFO"
        }
        catch {
            Write-Log "Error removing failure file for $ServiceName`: $($_.Exception.Message)" "ERROR"
        }
    }
}

# ================================
# MAIN SCRIPT EXECUTION
# ================================
Write-Log "Starting service monitor script" "INFO"
Write-Log "Testing Mode: $TestingMode" "INFO"

# Get hostname for alerts
$hostname = $env:COMPUTERNAME
Write-Log "Hostname: $hostname" "INFO"

# Check if this computer should be excluded from service monitoring
$shouldExclude = $false

foreach ($pattern in $excludePatterns) {
    if ($hostname -like "*$pattern*") {
        $shouldExclude = $true
        Write-Log "Computer hostname contains '$pattern' - skipping service monitoring" "INFO"
        break
    }
}

# Exit early if computer should be excluded
if ($shouldExclude) {
    Write-Log "Script execution completed - computer excluded from service monitoring" "INFO"
    Write-Log "----------------------------------------" "INFO"
    exit 0
}

# Parse services configuration
$servicesToCheck = $ServicesConfig.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
Write-Log "Services to check: $($servicesToCheck -join ', ')" "INFO"

if ($ServicesToRestart.Count -gt 0) {
    Write-Log "Services to auto-restart: $($ServicesToRestart -join ', ')" "INFO"
} else {
    Write-Log "No services configured for auto-restart" "INFO"
}

# Validate services exist on system
$validServices = @()
$invalidServices = @()

foreach ($serviceName in $servicesToCheck) {
    if ([string]::IsNullOrWhiteSpace($serviceName)) { continue }
    
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        $validServices += $serviceName
        Write-Log "Service '$serviceName' found and will be monitored" "INFO"
    }
    catch {
        $invalidServices += $serviceName
        Write-Log "Service '$serviceName' not found on system" "ERROR"
    }
}

# Send alert if any services are invalid
if ($invalidServices.Count -gt 0) {
    $invalidMessage = ":rotating_light: Configuration Error - $hostname`n"
    foreach ($invalidService in $invalidServices) {
        $invalidMessage += ":x: Service '$invalidService' not found`n"
    }
    $invalidMessage += ":white_check_mark: Continuing to monitor valid services`n"
    $invalidMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    Send-SlackAlert -Message $invalidMessage
}

# Exit if no valid services to monitor
if ($validServices.Count -eq 0) {
    Write-Log "No valid services to monitor. Exiting." "ERROR"
    exit 1
}

# Check status of valid services
$serviceStatuses = @()
$runningCount = 0
$stoppedCount = 0

# Get all services in one call for efficiency
$allServices = Get-Service -Name $validServices -ErrorAction SilentlyContinue

foreach ($serviceName in $validServices) {
    $service = $allServices | Where-Object { $_.Name -eq $serviceName }
    
    if ($service) {
        $status = @{
            Name = $serviceName
            Status = $service.Status
            IsRunning = ($service.Status -eq 'Running')
        }
        $serviceStatuses += $status
        
        if ($status.IsRunning) {
            $runningCount++
            Write-Log "Service '$serviceName' is RUNNING" "INFO"
        } else {
            $stoppedCount++
            Write-Log "Service '$serviceName' is STOPPED" "WARNING"
        }
    } else {
        Write-Log "Error checking service '$serviceName': Service not accessible" "ERROR"
        # Treat error as stopped service
        $status = @{
            Name = $serviceName
            Status = 'Error'
            IsRunning = $false
        }
        $serviceStatuses += $status
        $stoppedCount++
    }
}

# Determine if initial alert should be sent
$shouldSendAlert = $false
$alertMessage = ""

if ($TestingMode) {
    # Testing mode: Alert when ALL services are running (inverse logic to test alerts work)
    if ($stoppedCount -eq 0) {
        $shouldSendAlert = $true
        $alertMessage = ":white_check_mark: Service Test - All Services Running - $hostname`n"
        Write-Log "Testing mode: All services running - sending test alert" "INFO"
    } else {
        Write-Log "Testing mode: Not all services running - no alert sent" "INFO"
    }
} else {
    # Normal mode: Alert when ANY service is stopped
    if ($stoppedCount -gt 0) {
        $shouldSendAlert = $true
        $alertMessage = ":rotating_light: Service Alert - $hostname`n"
        Write-Log "Normal mode: $stoppedCount service(s) stopped - sending alert" "WARNING"
    } else {
        Write-Log "Normal mode: All services running - no alert needed" "INFO"
    }
}

# Build and send initial alert message if needed
if ($shouldSendAlert) {
    # Add service status details
    foreach ($status in $serviceStatuses) {
        if ($status.IsRunning) {
            $alertMessage += ":white_check_mark: $($status.Name): RUNNING`n"
        } else {
            $alertMessage += ":x: $($status.Name): STOPPED`n"
        }
    }
    
    # Add timestamp
    $alertMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    # Send the alert
    $alertSent = Send-SlackAlert -Message $alertMessage
    
    if (-not $alertSent) {
        Write-Log "Initial alert was not sent successfully" "ERROR"
    }
} else {
    Write-Log "No initial alert needed based on current service status" "INFO"
}

# ================================
# AUTO-RESTART LOGIC
# ================================

if ($TestingMode) {
    Write-Log "Testing mode enabled - skipping all restart attempts" "INFO"
} elseif ($ServicesToRestart.Count -eq 0) {
    Write-Log "No services configured for auto-restart - skipping restart logic" "INFO"
} else {
    Write-Log "Beginning auto-restart logic for stopped services" "INFO"
    
    # Process each service in restart list
    foreach ($serviceToRestart in $ServicesToRestart) {
        # Only process if service is in both monitoring list and is currently stopped
        $serviceStatus = $serviceStatuses | Where-Object { $_.Name -eq $serviceToRestart }
        
        if (-not $serviceStatus) {
            Write-Log "Service '$serviceToRestart' is in restart list but not in monitoring list - skipping" "WARNING"
            continue
        }
        
        if ($serviceStatus.IsRunning) {
            Write-Log "Service '$serviceToRestart' is running - no restart needed" "INFO"
            # Clean up any old failure tracking since service is now running
            Remove-FailureTracking -ServiceName $serviceToRestart
            continue
        }
        
        Write-Log "Processing restart logic for stopped service: $serviceToRestart" "INFO"
        
        # Check failure tracking
        $failureInfo = Get-FailureTracking -ServiceName $serviceToRestart
        $attemptCount = 1
        $shouldAttemptRestart = $true
        
        if ($failureInfo) {
            $minutesSinceLastAttempt = ((Get-Date) - $failureInfo.LastAttempt).TotalMinutes
            
            if ($minutesSinceLastAttempt -ge $FailureResetMinutes) {
                # Reset failure tracking
                Remove-FailureTracking -ServiceName $serviceToRestart
                Write-Log "Failure tracking reset for '$serviceToRestart' after $([math]::Round($minutesSinceLastAttempt)) minutes" "INFO"
                $attemptCount = 1
            } elseif ($failureInfo.AttemptCount -ge $MaxRestartAttempts) {
                # Max attempts reached, give up
                $giveUpMessage = ":rotating_light: Service Restart Abandoned - $hostname`n"
                $giveUpMessage += ":x: Giving up on $serviceToRestart after $($failureInfo.AttemptCount) failed attempts`n"
                $giveUpMessage += ":warning: Manual intervention required - service may be broken`n"
                $giveUpMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                
                Send-SlackAlert -Message $giveUpMessage
                Write-Log "Giving up on service '$serviceToRestart' after $($failureInfo.AttemptCount) attempts" "WARNING"
                $shouldAttemptRestart = $false
            } else {
                # Increment attempt count
                $attemptCount = $failureInfo.AttemptCount + 1
            }
        }
        
        if ($shouldAttemptRestart) {
            # Update failure tracking
            Set-FailureTracking -ServiceName $serviceToRestart -AttemptCount $attemptCount
            
            # Send attempt alert
            $attemptMessage = ":rotating_light: Service Restart Attempt - $hostname`n"
            $attemptMessage += ":arrows_counterclockwise: Attempting to restart $serviceToRestart (Attempt $attemptCount of $MaxRestartAttempts)`n"
            $attemptMessage += ":clock1: Will check status in $RestartWaitTimeSeconds seconds`n"
            $attemptMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            
            Send-SlackAlert -Message $attemptMessage
            Write-Log "Sending restart attempt alert for '$serviceToRestart' (attempt $attemptCount)" "INFO"
            
            # Attempt to start the service
            try {
                Write-Log "Executing Start-Service command for '$serviceToRestart'" "INFO"
                Start-Service -Name $serviceToRestart -ErrorAction Stop
                Write-Log "Start-Service command completed for '$serviceToRestart'" "INFO"
            }
            catch {
                # Handle restart command failure
                $errorMessage = $_.Exception.Message
                Write-Log "Start-Service failed for '$serviceToRestart': $errorMessage" "ERROR"
                
                # Check for permission-related errors
                if ($errorMessage -like "*Access*denied*" -or $errorMessage -like "*privilege*" -or $errorMessage -like "*permission*" -or $errorMessage -like "*unauthorized*") {
                    $permissionMessage = ":rotating_light: Service Restart Permission Error - $hostname`n"
                    $permissionMessage += ":lock: Insufficient privileges to restart $serviceToRestart`n"
                    $permissionMessage += ":mag: Check scheduled task permissions`n"
                    $permissionMessage += "Error: $errorMessage`n"
                    $permissionMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    
                    Send-SlackAlert -Message $permissionMessage
                } else {
                    $commandFailMessage = ":rotating_light: Service Restart Command Failed - $hostname`n"
                    $commandFailMessage += ":x: Restart command failed for $serviceToRestart`n"
                    $commandFailMessage += ":warning: Error: $errorMessage`n"
                    $commandFailMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    
                    Send-SlackAlert -Message $commandFailMessage
                }
                
                continue # Skip to next service
            }
            
            # Wait before checking status
            Write-Log "Waiting $RestartWaitTimeSeconds seconds before checking service status" "INFO"
            Start-Sleep -Seconds $RestartWaitTimeSeconds
            
            # Re-check service status
            try {
                $restartedService = Get-Service -Name $serviceToRestart -ErrorAction Stop
                $isNowRunning = ($restartedService.Status -eq 'Running')
                
                if ($isNowRunning) {
                    # Success - remove failure tracking
                    Remove-FailureTracking -ServiceName $serviceToRestart
                    
                    $successMessage = ":white_check_mark: Service Restart Success - $hostname`n"
                    $successMessage += ":white_check_mark: $serviceToRestart successfully restarted`n"
                    if ($attemptCount -gt 1) {
                        $successMessage += ":arrows_counterclockwise: Success on attempt $attemptCount`n"
                    }
                    $successMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    
                    Send-SlackAlert -Message $successMessage
                    Write-Log "Service '$serviceToRestart' successfully restarted" "SUCCESS"
                } else {
                    # Still stopped after restart attempt
                    $failMessage = ":x: Service Restart Failed - $hostname`n"
                    $failMessage += ":x: $serviceToRestart still stopped after restart attempt`n"
                    $failMessage += ":warning: Attempt $attemptCount of $MaxRestartAttempts failed`n"
                    $failMessage += "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    
                    Send-SlackAlert -Message $failMessage
                    Write-Log "Service '$serviceToRestart' still stopped after restart attempt $attemptCount" "WARNING"
                }
            }
            catch {
                Write-Log "Error re-checking service '$serviceToRestart' status: $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

# Log summary
Write-Log "Script execution completed. Services running: $runningCount, Services stopped: $stoppedCount" "INFO"
if (-not $TestingMode -and $ServicesToRestart.Count -gt 0) {
    Write-Log "Auto-restart processing completed for configured services" "INFO"
}
Write-Log "----------------------------------------" "INFO"
