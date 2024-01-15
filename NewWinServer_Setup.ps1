# Define a logging function
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Message
    )

    # Create the log directory if it doesn't exist
    $logDir = "C:\Temp"
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    # Define the log file path
    $logFile = Join-Path -Path $logDir -ChildPath "NewWinServer_Setup_v12.log"

    # Write the message to the log file
    Add-Content -Path $logFile -Value ("[" + (Get-Date).ToString() + "] " + $Message)
}

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
function Set-NetworkConfiguration {
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
function Set-IEEnhancedSecurityConfiguration {
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
function New-ExternalVSwitch {
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
        [SecureString]$DSRMPassword,
        [string]$SiteName,
        [string]$GlobalSubnet
    )
    try {
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
        Write-Host "Active Directory Domain Services role installed."
        $secureDSRMPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force
        Install-ADDSForest -DomainName $DomainName -SafeModeAdministratorPassword $secureDSRMPassword -Force
        Write-Host "Active Directory Domain Services configured."
    } catch {
        Write-Host "Error installing Domain Controller role: $_"
    }
}

#Function to Configure NTP Settings
function Set-NTPSettings {
    param (
        [string]$PDCName,
        [string[]]$NTPServers
    )
    try {
        $ntpServerList = $NTPServers -join ","
        Invoke-Command -ComputerName $PDCName -ScriptBlock {
            param ($ntpServerList)
            w32tm /config /manualpeerlist:$ntpServerList /syncfromflags:manual /reliable:YES /update
            Restart-Service w32time -Force
            Write-Host "NTP settings configured successfully on $using:PDCName."
        } -ArgumentList $ntpServerList
    } catch {
        Write-Host "Error configuring NTP settings on ${PDCName}: $_"
    }
}

# Function to Display Current Network Settings
function Display-CurrentNetworkSettings {
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'Ethernet' -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress
    $currentSubnetMask = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'Ethernet' -and $_.PrefixOrigin -ne 'WellKnown' }).PrefixLength
    $currentGateway = (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' -and $_.InterfaceAlias -eq 'Ethernet' }).NextHop
    $currentDNS = (Get-DnsClientServerAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).ServerAddresses -join ", "

    Write-Host "Current Network Settings:"
    Write-Host "IP Address: $currentIP"
    Write-Host "Subnet Mask: $currentSubnetMask"
    Write-Host "Gateway: $currentGateway"
    Write-Host "DNS: $currentDNS"
}

# Main Script Logic

# Check and display current hostname
$currentHostname = [System.Net.Dns]::GetHostName()
$changeHostname = Read-Host "Current Hostname is: $currentHostname. Would you like to change it? (Yes/No)"
if ($changeHostname -eq "Yes") {
    $hostname = Read-Host "Enter New Hostname"
    Rename-Computer -NewName $hostname
    Write-Log "Hostname changed to $hostname"
} else {
    $hostname = $currentHostname
    Write-Log "Hostname remains as $currentHostname"
}

# Prompt for server role
$serverRole = Read-Host "Enter Server Role (Hyper-V/DomainController)"

# Conditional prompts and configurations based on server role
if ($serverRole -eq "Hyper-V") {
    # Display current network settings for Hyper-V
    Display-CurrentNetworkSettings
    
    # Hyper-V specific network configuration prompts
    $ipAddress = Read-Host "Enter IP Address for Hyper-V"
    $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
    $gateway = Read-Host "Enter Gateway"
    $dns = Read-Host "Enter DNS"
    
    # Validate and apply network settings
    if (-not (Validate-IPAddress -IPAddress $ipAddress) -or -not (Validate-DNS -DNS $dns)) {
        Write-Host "Invalid network settings for Hyper-V."
        return
    }
    Set-NetworkConfiguration -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns

    # Hyper-V specific configuration calls
        Write-Log "Installing Hyper-V role..."
        Install-HyperVRole
        Write-Log "Creating external virtual switch..."
        New-ExternalVSwitch
    }

    # Hyper-V Domain Join Logic (if applicable)
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
if ($domainJoin -eq "Yes") {
    $credential = Get-Credential -Message "Enter credentials for domain join"
    Add-Computer -DomainName $domainName -Credential $credential
    Restart-Computer -Force
    Write-Log "Hyper-V host joined to the domain and restarted."
elseif ($serverRole -eq "DomainController") 

# Display current network settings for Domain Controller
Display-CurrentNetworkSettings

"DomainController"
    # Domain Controller specific configuration
    if ($serverRole -eq "DomainController") {
        Write-Log "Starting Domain Controller configuration..."

        # Display current network settings
        Display-CurrentNetworkSettings

        # Prompt for Domain Controller specific network settings
        $ipAddress = Read-Host "Enter IP Address for Domain Controller"
        $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
        $gateway = Read-Host "Enter Gateway"
        $dns = Read-Host "Enter DNS"
        
        # Validate network settings
        if (-not (Validate-IPAddress -IPAddress $ipAddress) -or -not (Validate-DNS -DNS $dns)) {
            Write-Host "Invalid network settings for Domain Controller."
        }
    }

    # Display current network settings for Domain Controller
    Display-CurrentNetworkSettings
    

    

    # Domain Controller specific network configuration prompts
$ipAddress = Read-Host "Enter IP Address for Domain Controller"
$subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
$gateway = Read-Host "Enter Gateway"
$dns = Read-Host "Enter DNS"

# Validate and apply network settings
if (-not (Validate-IPAddress -IPAddress $ipAddress) -or -not (Validate-DNS -DNS $dns)) {
    Write-Host "Invalid network settings for Domain Controller."
    return
}
Set-NetworkConfiguration -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns

# Additional Domain Controller specific configurations
$domainName = Read-Host "Enter Domain Name"
$dsrmPassword = Read-Host "Enter DSRM Password" -AsSecureString
$siteName = Read-Host "Enter Site Name"
$globalSubnet = Read-Host "Enter Global Subnet"

# Install Domain Controller Role and configure ADDS
Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
Write-Log "Active Directory Domain Services role installed and configured."

# Configure NTP Settings (if not using default NTP servers)
$useDefaultNTP = Read-Host "Use default NTP servers? (Yes/No)"
if ($useDefaultNTP -eq "No") {
    $ntpServers = Read-Host "Enter Comma Separated NTP Servers"
    Set-NTPSettings -PDCName $hostname -NTPServers $ntpServers
    Write-Log "NTP settings configured for Domain Controller."
}

# Domain join logic for Domain Controller
if ($domainJoin -eq "Yes") {
Write-Log "Joining server to the domain as a Domain Controller..."
        # Since the server is being configured as a Domain Controller, it will inherently join the domain as part of the promotion process
        # Additional logic for joining domain, if not covered in Install-DomainControllerRole
    }
}

# Common configurations for all roles
# Set RDP Settings (assuming RDP is to be enabled by default)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Set-IEEnhancedSecurityConfiguration -DisableIEEsc $true

# Additional common configurations can be placed here...

Write-Host "Configuration complete. Please review the log for details."


