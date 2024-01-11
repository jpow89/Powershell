# Function to Configure Network
function Configure-Network {
    param (
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNS
    )
    try {
        New-NetIPAddress -IPAddress $IPAddress -PrefixLength $SubnetMask -DefaultGateway $Gateway
        Set-DnsClientServerAddress -ServerAddresses $DNS
        Write-Host "Network configuration applied successfully."
    } catch {
        Write-Host "Error in network configuration: $_"
    }
}

# Function to Set RDP Settings
function Set-RDPSettings {
    param (
        [bool]$EnableRDP
    )
    try {
        $value = if ($EnableRDP) { 0 } else { 1 }
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value $value
        if ($EnableRDP) {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        } else {
            Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
        }
        Write-Host "RDP setting updated."
    } catch {
        Write-Host "Error configuring RDP settings: $_"
    }
}

# Function to Configure IE Enhanced Security
function Configure-IEEnhancedSecurity {
    param (
        [bool]$DisableIEEsc
    )
    try {
        $AdminKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
        $UserKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}'
        $value = if ($DisableIEEsc) { 0 } else { 1 }
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value $value
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value $value
        Write-Host "IE Enhanced Security Configuration updated."
    } catch {
        Write-Host "Error configuring IE Enhanced Security: $_"
    }
}

# Function to Install Hyper-V Role
function Install-HyperVRole {
    try {
        Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools
        Write-Host "Hyper-V role and features have been installed successfully."
    } catch {
        Write-Host "Error installing Hyper-V role: $_"
    }
}

# Function to Create External Virtual Switch for Hyper-V
function Create-ExternalVSwitch {
    try {
        $activeNic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        New-VMSwitch -Name "Ext_VSwitch01" -NetAdapterName $activeNic.Name -AllowManagementOS:$true
        Write-Host "External Virtual Switch 'Ext_VSwitch01' created successfully."
    } catch {
        Write-Host "Error creating External Virtual Switch: $_"
    }
}

# Function to Install Domain Controller Role
function Install-DomainControllerRole {
    param (
        [string]$DomainName,
        [string]$DSRMPassword,
        [string]$SiteName,
        [string]$GlobalSubnet
    )
    try {
        # Install AD DS Role
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
        Write-Host "Active Directory Domain Services role installed."

        # Configure AD DS
        $secureDSRMPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force
        Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $secureDSRMPassword -Force
        Write-Host "Active Directory Domain Services configured."

        # Configure Active Directory Sites and Services
        New-ADReplicationSite -Name $SiteName -ErrorAction Stop
        New-ADReplicationSubnet -Name $GlobalSubnet -Site $SiteName -ErrorAction Stop
        Write-Host "AD Sites and Services configured."

        # Configure DNS settings (example: creating a reverse lookup zone)
        $reverseZone = ($GlobalSubnet -split '/')[0] -replace '\.', '-' + ".in-addr.arpa"
        Add-DnsServerPrimaryZone -NetworkId $reverseZone -ReplicationScope Domain -ErrorAction Stop
        Write-Host "DNS reverse lookup zone created."

        # Additional DNS configurations as needed

    } catch {
        Write-Host "Error installing Domain Controller role: $_"
    }
}


# Function to Configure NTP Settings
function Configure-NTPSettings {
    param (
        [string]$PDCName,
        [string[]]$NTPServers
    )
    try {
        $ntpServerList = $NTPServers -join ","
        Invoke-Command -ComputerName $PDCName -ScriptBlock {
            w32tm /config /manualpeerlist:$using:ntpServerList /syncfromflags:manual /reliable:YES /update
            Restart-Service w32time -Force
        }
        Write-Host "NTP settings configured successfully on $PDCName."
    } catch {
        Write-Host "Error configuring NTP settings on $PDCName: $_"
    }
}

# Main Script

# Prompt for user inputs
$serverRole = Read-Host "Enter Server Role (Hyper-V/DomainController)"
$hostname = Read-Host "Enter Hostname"
$ipAddress = Read-Host "Enter IP Address"
$subnetMask = Read-Host "Enter Subnet Mask"
$gateway = Read-Host "Enter Gateway"
$dns = Read-Host "Enter DNS"
$domainName = Read-Host "Enter Domain Name"
$dsrmPassword = Read-Host "Enter DSRM Password"
$siteName = Read-Host "Enter Site Name"
$globalSubnet = Read-Host "Enter Global Subnet"
$ntpServers = @('0.us.pool.ntp.org', '1.us.pool.ntp.org', '2.us.pool.ntp.org', '3.us.pool.ntp.org')

# Configure Network
Configure-Network -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns

# Set RDP Settings (assuming RDP is to be enabled)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Configure-IEEnhancedSecurity -DisableIEEsc $true

# Check Server Role and perform specific configurations
switch ($serverRole) {
    "Hyper-V" {
        Install-HyperVRole
        Create-ExternalVSwitch
    }
    "DomainController" {
        Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
        Configure-NTPSettings -PDCName $hostname -NTPServers $ntpServers
    }
}

# Additional script logic...
# Error handling, logging, etc.
