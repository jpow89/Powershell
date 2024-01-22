# Auto-detect the domain name and domain controller
$domainName = (Get-ADDomain).DNSRoot
$dcName = (Get-ADDomainController).HostName

# Define the output file path using $PSScriptRoot
$outputPath = Join-Path -Path $PSScriptRoot -ChildPath "DomainController_Troubleshooting.txt"

# Start capturing the script output
Start-Transcript -Path $outputPath -Append

Write-Host "Domain: $domainName"
Write-Host "Domain Controller: $dcName"

# Check Services Status
function Check-Services {
    Write-Host "Checking status of DFS Replication and Netlogon services..."
    Get-Service -Name "DFSR", "Netlogon" | Format-Table -Property DisplayName, Status
}

# Force DFS Replication
function Force-DFSReplication {
    Write-Host "Forcing DFS Replication on $dcName..."
    repadmin /syncall $dcName /AdeP
}

# Check SYSVOL Share Accessibility
function Check-SYSVOL {
    Write-Host "Checking SYSVOL share accessibility on $dcName..."
    if (Test-Path "\\$dcName\sysvol") {
        Write-Host "SYSVOL share is accessible."
    } else {
        Write-Host "SYSVOL share is NOT accessible."
    }
}

# Check Event Logs
function Check-EventLogs {
    Write-Host "Checking System and DFS Replication event logs for errors..."
    Get-EventLog -LogName System -EntryType Error -Newest 10
    Get-WinEvent -LogName "DFS Replication" -MaxEvents 10 | Where-Object {$_.LevelDisplayName -eq "Error"}
}

# Script Execution
Write-Host "Starting Domain Controller Health Checks..."

Check-Services
Force-DFSReplication
Check-SYSVOL
Check-EventLogs

Write-Host "Checks Complete. Please review the output for any issues."

# Stop the transcript
Stop-Transcript
