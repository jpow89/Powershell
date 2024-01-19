function Remove-DnsRecords {
    param(
        [string]$dnsServer,    # DNS server to query
        [string]$oldServerName # The name of the server to remove
    )

    # Retrieve all DNS zones from the specified DNS server
    $dnsZones = Get-DnsServerZone -ComputerName $dnsServer

    foreach ($zone in $dnsZones) {
        Write-Host "Checking DNS records for $oldServerName in zone $($zone.ZoneName)..."
        try {
            $records = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ComputerName $dnsServer | 
                       Where-Object { $_.RecordData -match $oldServerName -or $_.HostName -eq $oldServerName }

            foreach ($record in $records) {
                Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -InputObject $record -Force -ComputerName $dnsServer
                Write-Host "Removed record $($record.HostName) from zone $($zone.ZoneName)."
            }
        } catch {
            Write-Host "An error occurred during DNS records removal in zone $($zone.ZoneName): $_"
        }
    }
}

# Example usage
$dnsServer = "YourDnsServerName" # Replace with your DNS server name
$oldServerName = "OldServerName"  # Replace with the name of the server to remove

# Function Definition for Check-GPOs
function Check-GPOs {
    param([string]$oldServerName)

    try {
        Write-Host "Checking for Group Policy Objects linked to $oldServerName..."
        $linkedGPOs = Get-GPO -All | Where-Object { $_.GPOStatus -ne 'AllSettingsDisabled' } | ForEach-Object { Get-GPPermissions -Guid $_.Id -TargetName $oldServerName -TargetType Computer -ErrorAction SilentlyContinue }
        if ($linkedGPOs) {
            Write-Host "Found linked GPOs: $($linkedGPOs.Name)"
        } else {
            Write-Host "No GPOs linked to $oldServerName found."
        }
    } catch {
        Write-Host "An error occurred while checking for linked GPOs: $_"
    }
}

function Start-NtdsutilCleanup {
    param([string]$oldServerName)

    Write-Host "Please manually perform metadata cleanup using NTDSUTIL..."
    $scriptBlock = {
        cmd /c "ntdsutil"
        # The commands below are just an example. They won't actually execute in ntdsutil.
        # This is a placeholder to show where you would put any automated commands, if possible.
        # Example: 'echo metadata cleanup' | ntdsutil
        # Reminder for users to follow the manual steps provided in the PowerShell window.
        Write-Host "Follow the NTDSUTIL instructions provided in the PowerShell window."
        Write-Host "After completing the steps in the NTDSUTIL, close this window manually."
    }
    
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $scriptBlock
    
    # Provide instructions for NTDSUTIL
    Write-Host "NTDSUTIL Instructions:"
    Write-Host "1. Type 'metadata cleanup' and press Enter."
    Write-Host "2. Type 'connections' and press Enter."
    Write-Host "3. Type 'connect to server <AnotherDCName>' (replace <AnotherDCName> with the name of a working DC) and press Enter."
    Write-Host "4. Type 'quit' and press Enter."
    Write-Host "5. Type 'select operation target' and press Enter."
    Write-Host "6. Type 'list domains' and press Enter."
    Write-Host "7. After the domains are listed, type 'select domain <number>' (replace <number> with the appropriate number for your domain) and press Enter."
    Write-Host "8. Type 'list sites' and press Enter."
    Write-Host "9. After the sites are listed, type 'select site <number>' (replace <number> with the appropriate number for your site) and press Enter."
    Write-Host "10. Type 'list servers in site' and press Enter."
    Write-Host "11. After the servers are listed, type 'select server <number>' (replace <number> with the number corresponding to $oldServerName) and press Enter."
    Write-Host "12. Type 'quit' and press Enter."
    Write-Host "13. Type 'remove selected server' and press Enter."
    Write-Host "14. Follow the prompts to confirm and complete the removal."
}

function Remove-ServerFromSitesAndServices {
    param(
        [string]$oldServerName,
        [string]$domainName  # Assuming this is in DNS format like 'example.com'
    )

    try {
        # Convert the domain name to DN format for LDAP path
        $domainDN = "DC=" + ($domainName -replace "\.", ",DC=")

        # Construct the search base for finding the server object in AD Sites and Services
        $searchBase = "CN=Sites,CN=Configuration,$domainDN"

        # Find the server object in AD Sites and Services
        $serverObject = Get-ADObject -Filter { ObjectClass -eq 'server' -and Name -eq $oldServerName } -SearchBase $searchBase -Properties *

        if ($serverObject) {
            # Confirm removal
            $confirmation = Read-Host "Are you sure you want to remove $oldServerName from Sites and Services? (yes/no)"
            if ($confirmation -eq "yes") {
                # Remove the server object
                Remove-ADObject -Identity $serverObject.DistinguishedName -Recursive -Confirm:$false
                Write-Host "$oldServerName removed from Sites and Services."
            } else {
                Write-Host "Operation cancelled by user."
            }
        } else {
            Write-Host "Server object for $oldServerName not found."
        }
    } catch {
        Write-Host "An error occurred: $_"
    }
}

# Main script execution
$domainName = Read-Host "Please enter the domain name"
$oldServerName = Read-Host "Please enter the old server name"

# Call the functions
Remove-DnsRecords -dnsServer $dnsServer -oldServerName $oldServerName
Check-GPOs -oldServerName $oldServerName
Start-NtdsutilCleanup
Remove-ServerFromSitesAndServices -oldServerName $oldServerName -domainName $domainName

Write-Host "Script execution completed. Please ensure to follow the manual steps for NTDSUTIL."
