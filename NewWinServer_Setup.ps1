Part 1: Function Definitions

# Function to Validate IP Address
function Validate-IPAddress {
    param (
        [string]$IPAddress
    )
    return $IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$'
}

# Function to Validate DNS Address
function Validate-DNS {
    param (
        [string]$DNS
    )
    return Validate-IPAddress -IPAddress $DNS
}

# Function to Configure Network
function Configure-Network {
    param (
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNS
    )
    if (-not (Validate-IPAddress -IPAddress $IPAddress)) {
        Write-Host "Invalid IP Address format."
        return
    }
    if (-not (Validate-DNS -DNS $DNS)) {
        Write-Host "Invalid DNS format."
        return
    }
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
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
        Write-Host "Active Directory Domain Services role installed."
        $secureDSRMPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force
        Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $secureDSRMPassword -Force
        Write-Host "Active Directory Domain Services configured."
        # Additional configurations as needed
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
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
        Write-Host "Active Directory Domain Services role installed."
        $secureDSRMPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force
        Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $secureDSRMPassword -Force
        Write-Host "Active Directory Domain Services configured."
        # Additional configurations as needed
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

Part 2: Main Script Structure

# Main Script

# Prompt for server role
$serverRole = Read-Host "Enter Server Role (Hyper-V/DomainController)"

# Conditional prompts based on server role
if ($serverRole -eq "Hyper-V") {
    $hostname = Read-Host "Enter Hostname for Hyper-V"
    $ipAddress = Read-Host "Enter IP Address"
    $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
    $gateway = Read-Host "Enter Gateway"
    $dns = Read-Host "Enter DNS"
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    
    # Hyper-V specific configuration calls
    # ...

} elseif ($serverRole -eq "DomainController") {
    $hostname = Read-Host "Enter Hostname for Domain Controller"
    $ipAddress = Read-Host "Enter IP Address"
    $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
    $gateway = Read-Host "Enter Gateway"
    $dns = Read-Host "Enter DNS"
    $domainName = Read-Host "Enter Domain Name"
    $dsrmPassword = Read-Host "Enter DSRM Password"
    $siteName = Read-Host "Enter Site Name"
    $globalSubnet = Read-Host "Enter Global Subnet"
    $ntpServers = @('0.us.pool.ntp.org', '1.us.pool.ntp.org', '2.us.pool.ntp.org', '3.us.pool.ntp.org')
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    
    # Domain Controller specific configuration calls
    # ...
}

# Configure Network based on role
if ($serverRole -eq "Hyper-V" -or $serverRole -eq "DomainController") {
    Configure-Network -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns
}

# Set RDP Settings (assuming RDP is to be enabled)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Configure-IEEnhancedSecurity -DisableIEEsc $true

# Role-specific configurations
switch ($serverRole) {
    "Hyper-V" {
        Install-HyperVRole
        Create-ExternalVSwitch
        # Additional Hyper-V specific configurations
    }
    "DomainController" {
        Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
        Configure-NTPSettings -PDCName $hostname -NTPServers $ntpServers
        # Additional Domain Controller specific configurations
    }
}

# Domain Join Logic
if ($domainJoin -eq "Yes") {
    if ($serverRole -eq "DomainController") {
        # Logic for joining the domain controller to the domain
        # This might include additional steps specific to domain controllers
    } else {
        # General domain join logic for other server roles
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
    }
}

# Additional script logic...
# Error handling, logging, etc.
