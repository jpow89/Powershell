# Function Definitions
# --- Backup AD, DNS, GP ---
function Backup-ADAndDNS {
    param(
        [string]$backupPath,
        [string]$logPath = "C:\BackupLog.txt"
    )

    if (-not (Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath
    }

    try {
        # Backup Active Directory
        $adBackupPath = Join-Path -Path $backupPath -ChildPath "ADBackup"
        if (-not (Test-Path -Path $adBackupPath)) {
            New-Item -ItemType Directory -Path $adBackupPath
        }
        Add-Content -Path $logPath -Value "Backing up Active Directory..."
        & wbadmin start systemstatebackup -backupTarget:$adBackupPath

        # Backup DNS
        $dnsBackupPath = Join-Path -Path $backupPath -ChildPath "DNSBackup"
        if (-not (Test-Path -Path $dnsBackupPath)) {
            New-Item -ItemType Directory -Path $dnsBackupPath
        }
        Add-Content -Path $logPath -Value "Backing up DNS..."
        Get-DnsServerZone | Export-Clixml -Path (Join-Path -Path $dnsBackupPath -ChildPath "DNSZones.xml")

        # Backup Group Policy Objects
        $gpoBackupPath = Join-Path -Path $backupPath -ChildPath "GPOBackup"
        if (-not (Test-Path -Path $gpoBackupPath)) {
            New-Item -ItemType Directory -Path $gpoBackupPath
        }
        Add-Content -Path $logPath -Value "Backing up Group Policy Objects..."
        Backup-Gpo -All -Path $gpoBackupPath

        Add-Content -Path $logPath -Value "Backup completed successfully."
    } catch {
        Add-Content -Path $logPath -Value "An error occurred during backup: $_"
        throw
    }
}

# --- Remove-DnsRecords Function ---
function Remove-DnsRecords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$dnsServer,

        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath = "C:\DNSCleanupLog.txt"
    )

    if (-not (Resolve-DnsName $dnsServer -ErrorAction SilentlyContinue)) {
        Add-Content -Path $logPath -Value "DNS Server $dnsServer not found. Exiting."
        return
    }

    Add-Content -Path $logPath -Value "Starting DNS cleanup for $oldServerName on $dnsServer"

    try {
        $dnsZones = Get-DnsServerZone -ComputerName $dnsServer

        foreach ($zone in $dnsZones) {
            Add-Content -Path $logPath -Value "Checking zone $($zone.ZoneName)..."

            # Retrieve all records from the zone
            $records = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName $dnsServer

            # Filter records related to the old server
            $targetRecords = $records | Where-Object {
                ($_.HostName -eq $oldServerName) -or
                ($_.RecordData -match $oldServerName) -or
                ($_.RecordType -eq 'SRV' -and $_.RecordData -match $oldServerName)
            }

            foreach ($record in $targetRecords) {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -InputObject $record -Force -ComputerName $dnsServer
                Add-Content -Path $logPath -Value "Removed record $($record.RecordType) $($record.HostName) from zone $($zone.ZoneName)."
            }

            # Check and update NS records
            $nsRecords = $records | Where-Object { $_.RecordType -eq 'NS' -and $_.RecordData.NameServer -match $oldServerName }
            foreach ($nsRecord in $nsRecords) {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -InputObject $nsRecord -Force -ComputerName $dnsServer
                Add-Content -Path $logPath -Value "Removed NS record pointing to $oldServerName from zone $($zone.ZoneName)."
            }
        }
    } catch {
        Add-Content -Path $logPath -Value "An error occurred during DNS records removal: $_"
    }

    Add-Content -Path $logPath -Value "DNS cleanup completed for $oldServerName on $dnsServer"
}

# --- Check for and remove old domain controller from the Name Servers tab for each DNS Zone ---
function Update-NameServers {
    param(
        [Parameter(Mandatory=$true)]
        [string]$dnsServer,

        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath
    )

    $dnsZones = Get-DnsServerZone -ComputerName $dnsServer

    foreach ($zone in $dnsZones) {
        try {
            $nsRecords = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -RRType "NS" -ComputerName $dnsServer |
                         Where-Object { $_.RecordData.NameServer -eq "$oldServerName.asch.local" }

            foreach ($nsRecord in $nsRecords) {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -InputObject $nsRecord -Force -ComputerName $dnsServer
                Add-Content -Path $logPath -Value "Removed NS record for $oldServerName from zone $($zone.ZoneName)."
            }
        } catch {
            Add-Content -Path $logPath -Value "Error while updating NS records in zone $($zone.ZoneName): $_"
        }
    }
}

# --- Check-GPOs Function ---
function Check-GPOs {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath = "C:\DomainCleanupLog.txt"
    )

    Add-Content -Path $logPath -Value "Starting GPO checks for $oldServerName..."

    try {
        $gpos = Get-GPO -All -ErrorAction Stop
        $linkedGPOs = $gpos | Where-Object { $_.GPOStatus -ne 'AllSettingsDisabled' } | 
                      ForEach-Object { Get-GPPermissions -Guid $_.Id -TargetName $oldServerName -TargetType Computer -ErrorAction SilentlyContinue }

        if ($linkedGPOs) {
            $linkedGPOs | ForEach-Object { Add-Content -Path $logPath -Value "Linked GPO found: $($_.DisplayName)" }
        } else {
            Add-Content -Path $logPath -Value "No GPOs linked to $oldServerName found."
        }
    } catch {
        Add-Content -Path $logPath -Value "Error occurred while checking GPOs: $_"
    }

    Add-Content -Path $logPath -Value "GPO check completed for $oldServerName."
}

# --- Start-NtdsutilCleanup Function ---
function Start-NtdsutilCleanup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath = "C:\NTDSUtilLog.txt"
    )

    Add-Content -Path $logPath -Value "Starting NTDSUTIL Cleanup process for $oldServerName..."

    $instructions = @"
Please follow these instructions for NTDSUTIL:

1. Open a Command Prompt as Administrator.
2. Type 'ntdsutil' and press Enter.
3. Type 'metadata cleanup' and press Enter.
4. Type 'connections' and press Enter.
5. Type 'connect to server <AnotherDCName>' and press Enter.
   Replace <AnotherDCName> with the name of a working DC.
6. Type 'quit' and press Enter.
7. Type 'select operation target' and press Enter.
8. Type 'list domains' and press Enter.
9. Type 'select domain <number>' and press Enter.
   Replace <number> with the number for your domain.
10. Type 'list sites' and press Enter.
11. Type 'select site <number>' and press Enter.
    Replace <number> with the number for your site.
12. Type 'list servers in site' and press Enter.
13. Type 'select server <number>' and press Enter.
    Replace <number> with the number for $oldServerName.
14. Type 'quit' and press Enter.
15. Type 'remove selected server' and press Enter.
16. Follow the prompts to confirm and complete the removal.

After completing these steps, close the Command Prompt.
"@

    Write-Host $instructions
    Add-Content -Path $logPath -Value "Provided NTDSUTIL instructions to the user."
    Add-Content -Path $logPath -Value "User instructed to follow manual steps and close the Command Prompt upon completion."
    Write-Host "Please check the log file at $logPath for a record of these instructions."
}

# --- Remove-ServerFromSitesAndServices Function ---
function Remove-ServerFromSitesAndServices {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [Parameter(Mandatory=$true)]
        [string]$domainName,

        [string]$logPath = "C:\ADCleanupLog.txt"
    )

    Add-Content -Path $logPath -Value "Starting removal of $oldServerName from Sites and Services..."

    try {
        $domainDN = "DC=" + ($domainName -replace "\.", ",DC=")
        $searchBase = "CN=Sites,CN=Configuration,$domainDN"
        $serverObject = Get-ADObject -Filter { ObjectClass -eq 'server' -and Name -eq $oldServerName } -SearchBase $searchBase -Properties *

        if ($serverObject) {
            $confirmation = Read-Host "Confirm removal of $oldServerName from Sites and Services (yes/no)"
            Add-Content -Path $logPath -Value "User prompted for confirmation to remove $oldServerName."

            if ($confirmation -eq "yes") {
                Remove-ADObject -Identity $serverObject.DistinguishedName -Recursive -Confirm:$false
                Add-Content -Path $logPath -Value "$oldServerName removed from Sites and Services."
                Write-Host "$oldServerName removed from Sites and Services."
            } else {
                Add-Content -Path $logPath -Value "Operation cancelled by user."
                Write-Host "Operation cancelled by user."
            }
        } else {
            Add-Content -Path $logPath -Value "Server object for $oldServerName not found."
            Write-Host "Server object for $oldServerName not found."
        }
    } catch {
        Add-Content -Path $logPath -Value "An error occurred: $_"
        Write-Host "An error occurred: $_"
    }
}

# Cleanup in Active Directory Users and Computers (ADUC)
function Check-DCinADUC {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath = "C:\ADUCCleanupLog.txt"
    )

    $domain = (Get-ADDomain).DNSRoot
    $domainController = (Get-ADDomainController -Discover -NextClosestSite).HostName

    Add-Content -Path $logPath -Value "Domain detected: $domain"
    Add-Content -Path $logPath -Value "Using Domain Controller: $domainController"

    try {
        $dcObject = Get-ADObject -Filter { ObjectClass -eq 'computer' -and Name -eq $oldServerName } -SearchBase "OU=Domain Controllers,DC=${domain -replace '\.',',DC='}"

        if ($dcObject) {
            Add-Content -Path $logPath -Value "$oldServerName is still listed in ADUC. Manual removal may be required."
        } else {
            Add-Content -Path $logPath -Value "$oldServerName is not found in the Domain Controllers OU."
        }
    } catch {
        Add-Content -Path $logPath -Value "Error checking ADUC: $_"
    }
}

# Checking FSMO Roles
function Check-FSMORoles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$logPath = "C:\FSMORolesCheckLog.txt"
    )

    try {
        $fsmoRoles = netdom query fsmo
        if ($fsmoRoles -match $oldServerName) {
            Add-Content -Path $logPath -Value "FSMO roles are still assigned to $oldServerName. Manual intervention required."
        } else {
            Add-Content -Path $logPath -Value "FSMO roles are not assigned to $oldServerName."
        }
    } catch {
        Add-Content -Path $logPath -Value "Error checking FSMO roles: $_"
    }
}

# Checking DNS Delegation
function Check-DNSDelegation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$oldServerName,

        [string]$dnsServer,

        [string]$logPath = "C:\DNSDelegationLog.txt"
    )

    try {
        $nsRecords = Get-DnsServerResourceRecord -ZoneName $dnsServer -RRType NS | Where-Object { $_.RecordData.NameServer -eq $oldServerName }
        
        if ($nsRecords) {
            Add-Content -Path $logPath -Value "DNS delegation for $oldServerName found. Review and update DNS delegation as necessary."
        } else {
            Add-Content -Path $logPath -Value "No DNS delegation for $oldServerName found."
        }
    } catch {
        Add-Content -Path $logPath -Value "Error checking DNS delegation: $_"
    }
}

# Main Script Execution

# Gather required information from the user
$dnsServer = Read-Host "Please enter the DNS server name"
$domainName = Read-Host "Please enter the domain name (in DNS format like 'example.com')"
$oldServerName = Read-Host "Please enter the old server name"

# Define backup path
$backupPath = "C:\DomainController_Cleanup\Backups"

# Base directory for logs
$logBasePath = "C:\DomainController_Cleanup"

# Create the base directory if it doesn't exist
if (-not (Test-Path -Path $logBasePath)) {
    New-Item -ItemType Directory -Path $logBasePath
}

# Define log file paths using the base path
$dnsLogPath = Join-Path -Path $logBasePath -ChildPath "DNSCleanupLog.txt"
$gpoLogPath = Join-Path -Path $logBasePath -ChildPath "DomainCleanupLog.txt"
$ntdsutilLogPath = Join-Path -Path $logBasePath -ChildPath "NTDSUtilLog.txt"
$adCleanupLogPath = Join-Path -Path $logBasePath -ChildPath "ADCleanupLog.txt"
$aducLogPath = Join-Path -Path $logBasePath -ChildPath "ADUCCleanupLog.txt"
$fsmoLogPath = Join-Path -Path $logBasePath -ChildPath "FSMORolesCheckLog.txt"
$dnsDelegationLogPath = Join-Path -Path $logBasePath -ChildPath "DNSDelegationLog.txt"

# Backup function before main script execution
Backup-ADAndDNS -backupPath $backupPath

# Call the functions with the gathered information and log paths
Remove-DnsRecords -dnsServer $dnsServer -oldServerName $oldServerName -logPath $dnsLogPath
Check-GPOs -oldServerName $oldServerName -logPath $gpoLogPath
Start-NtdsutilCleanup -oldServerName $oldServerName -logPath $ntdsutilLogPath
Remove-ServerFromSitesAndServices -oldServerName $oldServerName -domainName $domainName -logPath $adCleanupLogPath

# New function calls
Check-DCinADUC -oldServerName $oldServerName -logPath $aducLogPath
Check-FSMORoles -oldServerName $oldServerName -logPath $fsmoLogPath
Check-DNSDelegation -oldServerName $oldServerName -dnsServer $dnsServer -logPath $dnsDelegationLogPath

Write-Host "Script execution completed. Please review the log files for details."



