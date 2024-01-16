# PowerShell Script to Configure NTP Synchronization in Active Directory

# Script variables
$logFile = "C:\Logs\GPTimeSync\GPTimeSync.log"
$TimeServers = "0.us.pool.ntp.org,0x8 1.us.pool.ntp.org,0x8 2.us.pool.ntp.org,0x8 3.us.pool.ntp.org,0x8"
$PDCeGPOName = "PDC NTP Sync"
$WmiFilterName = "PDC Emulator Filter"
$WmiFilterDescription = "Filter for PDC Emulator"
$WmiFilterQuery = "Select * from Win32_ComputerSystem where DomainRole = 5"

# Ensures the log directory exists
$logDir = Split-Path -Path $logFile -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory
    Write-Log "Created log directory: $logDir"
}

# Function definitions

# Function to write logs
function Write-Log {
    Param ([string]$message)
    Add-Content -Path $logFile -Value "$(Get-Date) - $message"
}

# Function to create WMI Filter
function New-WmiFilter {
    param (
        [string]$FilterName,
        [string]$Description,
        [string]$Query
    )
    try {
        $existingFilter = Get-GPOWmiFilter -Name $FilterName -ErrorAction SilentlyContinue
        if ($null -eq $existingFilter) {
            Write-Log "Creating WMI Filter: $FilterName"
            New-GPOWmiFilter -Name $FilterName -Description $Description -Query $Query -Namespace "root\CIMv2"
            Write-Log "WMI Filter created successfully: $FilterName"
        } else {
            Write-Log "WMI Filter already exists: $FilterName"
        }
    } catch {
        Write-Log "Error creating WMI Filter: $_"
        throw
    }
}

function New-GPOConfiguration {
    param (
        [string]$GPOName,
        [string]$NtpServer,
        [string]$OUPath,
        [string]$WmiFilterName
    )
    try {
        $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if ($null -eq $gpo) {
            Write-Log "Creating GPO: $GPOName"
            $gpo = New-GPO -Name $GPOName
            Set-GPRegistryValue -Name $GPOName -Key "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ValueName "NtpServer" -Type String -Value $NtpServer
            Set-GPRegistryValue -Name $GPOName -Key "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ValueName "Type" -Type String -Value "NTP"
            Set-GPLink -Name $GPOName -Target $OUPath -LinkEnabled Yes
            $wmiFilter = Get-GPOWmiFilter -Name $WmiFilterName
            Set-GPO -Name $GPOName -WmiFilter $wmiFilter
            Write-Log "GPO created and configured successfully: $GPOName"
        } else {
            Write-Log "GPO already exists: $GPOName"
        }
    } catch {
        Write-Log "Error creating or configuring GPO: $_"
        throw
    }
}

# Main script execution
try {
    # Import GroupPolicy module
    Import-Module GroupPolicy

    # Detect domain name
    $domain = (Get-ADDomain).DNSRoot
    Write-Log "Domain detected: $domain"

    # Set OU path
    $domainParts = $domain -split "\."
    $ouPath = "OU=Domain Controllers" + ($domainParts | ForEach-Object { ",DC=$_" }) -join ""
    Write-Log "OU path set to: $ouPath"
    
    # Create WMI Filter
    New-WmiFilter -FilterName $WmiFilterName -Description $WmiFilterDescription -Query $WmiFilterQuery

    # Create and Configure GPO
    New-GPOConfiguration -GPOName $PDCeGPOName -NtpServer $TimeServers -OUPath $ouPath -WmiFilterName $WmiFilterName

    Write-Log "Script execution completed successfully."
} catch {
    Write-Log "Error occurred in script execution: $_"
    exit
}

# End of Script
