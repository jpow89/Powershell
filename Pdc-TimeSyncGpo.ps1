# Import GroupPolicy and ActiveDirectory modules
Import-Module GroupPolicy
Import-Module ActiveDirectory

# Create a new GPO
$gpoName = "PDC NTP Sync"
$gpo = New-GPO -Name $gpoName -Comment "GPO to configure NTP settings for PDC"

# Define the NTP registry settings
$ntpSettings = @{
    "NtpServer"                = "0.us.pool.ntp.org,0x8 1.us.pool.ntp.org,0x8 2.us.pool.ntp.org,0x8 3.us.pool.ntp.org,0x8";
    "Type"                     = "NTP";
    "CrossSiteSyncFlags"       = "2";
    "ResolvePeerBackoffMinutes"= "15";
    "ResolvePeerBackoffMaxTimes"= "7";
    "SpecialPollInterval"      = "3600";
    "EventLogFlags"            = "0";
}

# Configure the GPO with NTP settings
foreach ($key in $ntpSettings.Keys) {
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ValueName $key -Value $ntpSettings[$key] -Type String
}

# Enable Windows NTP Client and Server
Set-GPRegistryValue -Name $gpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" -ValueName "Enabled" -Value 1 -Type DWORD
Set-GPRegistryValue -Name $gpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -ValueName "Enabled" -Value 1 -Type DWORD

# Get the domain name in DNS format
$domainName = (Get-ADDomain).DNSRoot

# Split the domain name into its components and format it for LDAP path
$domainComponents = $domainName -split "\."
$dcPath = ($domainComponents | ForEach-Object { "DC=$_" }) -join ','

# Construct the distinguished name for the Domain Controllers OU
$domainControllersOU = "OU=Domain Controllers,$dcPath"

# Attempt to link the GPO to the Domain Controllers OU
try {
    New-GPLink -Name $gpoName -Target $domainControllersOU
    Write-Host "GPO '$gpoName' created and linked to the Domain Controllers OU successfully."
} catch {
    Write-Host "Error linking GPO to the Domain Controllers OU: $_"
}
