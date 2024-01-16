# Define a logging function
# This function creates a log file and records messages to it, useful for tracking script execution
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

# Centralized Error Handling
function Handle-Error {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ErrorMessage,
        [Parameter(Mandatory=$true)]
        [string] $FunctionName
    )
	
	$timestampedMessage = "[" + (Get-Date).ToString() + "] Error in $FunctionName: $ErrorMessage"
    Write-Log "Error in $FunctionName: $ErrorMessage"
    Write-Host "An error occurred in $FunctionName. Please check the log for details."
}

# Function to Backup Current Network Settings
function Backup-NetworkSettings {
    $backupFile = Join-Path -Path "C:\Temp" -ChildPath "NetworkSettingsBackup.json"
    $currentSettings = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'Ethernet' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object IPAddress, PrefixLength, InterfaceIndex
    $currentSettings | ConvertTo-Json | Set-Content -Path $backupFile
    Write-Log "Network settings backed up."
}

# Function to Restore Network Settings from Backup
function Restore-NetworkSettings {
    $backupFile = Join-Path -Path "C:\Temp" -ChildPath "NetworkSettingsBackup.json"
    if (Test-Path $backupFile) {
        $settings = Get-Content -Path $backupFile | ConvertFrom-Json
        New-NetIPAddress -IPAddress $settings.IPAddress -PrefixLength $settings.PrefixLength -InterfaceIndex $settings.InterfaceIndex -Confirm:$false
        Write-Log "Network settings restored from backup."
    } else {
        Write-Log "No network backup file found."
    }
}

# Function to Validate IP Address
# Validates the format of an IP address to ensure it's in the correct structure
function Validate-IPAddress {
    param (
        [string]$IPAddress
    )
    return $IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$'
}

# Function to Validate DNS Address
# Utilizes the IP address validation function to validate DNS addresses
function Validate-DNS {
    param (
        [string]$DNS
    )
    return Validate-IPAddress -IPAddress $DNS
}

# Function to Configure Network
# Configures the network settings including IP address, subnet mask, gateway, and DNS
# Validates the input and applies the configuration
function Set-NetworkConfiguration {
    param (
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNS
    )
	try {
        # Backup current network settings before making changes
        Backup-NetworkSettings
    if (-not (Validate-IPAddress -IPAddress $IPAddress)) {
        Write-Log "Invalid IP Address format."
        return
    }
    if (-not (Validate-DNS -DNS $DNS)) {
        Write-Log "Invalid DNS format."
        return
    }
    try {
        New-NetIPAddress -IPAddress $IPAddress -PrefixLength $SubnetMask -DefaultGateway $Gateway
        Set-DnsClientServerAddress -ServerAddresses $DNS
        Write-Log "Network configuration applied successfully."
    } catch {
        # If something goes wrong, restore the original network settings
		Restore-NetworkSettings
		Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Set-NetworkConfiguration"
    }
}

# Function to Set RDP Settings
# Enables or disables Remote Desktop Protocol on the server and updates the firewall settings accordingly
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
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Set-RDPSettings"
    }
}

# Function to Configure IE Enhanced Security
# Enables or disables Internet Explorer Enhanced Security Configuration based on the input
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
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Set-IEEnhancedSecurityConfiguration"
    }
}

# Function to Install Hyper-V Role
# Installs the Hyper-V role along with all sub-features and management tools
function Install-HyperVRole {
    try {
        Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools
        Write-Host "Hyper-V role and features have been installed successfully."
    } catch {
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Install-HyperVRole"
    }
}

# Function to Create External Virtual Switch for Hyper-V
# Creates a new external virtual switch for Hyper-V, allowing VMs to connect to the external network
function New-ExternalVSwitch {
    try {
        $activeNic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        New-VMSwitch -Name "Ext_VSwitch01" -NetAdapterName $activeNic.Name -AllowManagementOS:$true
        Write-Host "External Virtual Switch 'Ext_VSwitch01' created successfully."
        } catch {
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "New-ExternalVSwitch"
        }
        }

# Function to Install Domain Controller Role  
# Installs and configures the Active Directory Domain Services role
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
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Install-DomainControllerRole"
    }
}

#Function to Configure NTP Settings
# Sets up NTP settings on the Primary Domain Controller, synchronizing time across the network
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
        Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Set-NTPSettings"
    }
}

# Function to Display current hostname.
function Get-AndChangeHostname {
    $currentHostname = [System.Net.Dns]::GetHostName()
    $changeHostname = Read-Host "Current Hostname is: $currentHostname. Would you like to change it? (Yes/No)"
    if ($changeHostname -eq "Yes") {
        $hostname = Read-Host "Enter New Hostname"
        Rename-Computer -NewName $hostname
        Write-Log "Hostname changed to $hostname"
        $reboot = Read-Host "Do you want to reboot now? (Yes/No)"
        if ($reboot -eq "Yes") {
            Restart-Computer -Force
        }
    } else {
        $hostname = $currentHostname
        Write-Log "Hostname remains as $currentHostname"
    }
}

# Function to Display Current Network Settings
# Retrieves and displays the current network configuration of the server
function Display-CurrentNetworkSettings {
    $activeInterface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $activeInterface.Name -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress
    $currentSubnetMask = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $activeInterface.Name -and $_.PrefixOrigin -ne 'WellKnown' }).PrefixLength
    $currentGateway = (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' -and $_.InterfaceAlias -eq $activeInterface.Name }).NextHop
    $currentDNS = (Get-DnsClientServerAddress | Where-Object { $_.InterfaceAlias -eq $activeInterface.Name }).ServerAddresses -join ", "

    Write-Host "Current Network Settings:"
    Write-Host "IP Address: $currentIP"
    Write-Host "Subnet Mask: $currentSubnetMask"
    Write-Host "Gateway: $currentGateway"
    Write-Host "DNS: $currentDNS"
}

# Main Script Logic
# This section contains the primary logic of the script, starting with hostname configuration
# It prompts the user for server role and executes role-specific configurations

# Check and display current hostname, prompt for change if necessary
# Retrieves the current hostname and offers the user an option to change it
Get-AndChangeHostname

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

    # Hyper-V Domain Join Logic
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    if ($domainJoin -eq "Yes") {
        $domainName = Read-Host "Enter the domain name to join"
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
        Write-Log "Hyper-V host joined to the domain: $domainName and restarted."
    }
} elseif ($serverRole -eq "DomainController") {
    # Domain Controller specific configuration

    # Display current network settings
    Display-CurrentNetworkSettings

    # Prompt for Domain Controller specific network settings
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
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    if ($domainJoin -eq "Yes") {
        Write-Log "Joining server to the domain as a Domain Controller..."
        # Additional logic for joining domain, if not covered in Install-DomainControllerRole
        # Ensure this logic is implemented as per your requirements
    }

    # Additional Domain Join Logic for Domain Controller
    $domainType = Read-Host "Is this a New Domain or Existing Domain? (New/Existing)"
    
    if ($domainType -eq "New") {
        # Logic for creating a new domain (already covered in your script)
    } elseif ($domainType -eq "Existing") {
        # Logic for adding to an existing domain
        $existingDomainName = Read-Host "Enter the existing domain name"
        $domainControllerCredential = Get-Credential -Message "Enter credentials for joining the existing domain"
        
        try {
            Install-ADDSDomainController -DomainName $existingDomainName -Credential $domainControllerCredential
            Write-Log "Added new Domain Controller to existing domain: $existingDomainName"
        } catch {
            Handle-Error -ErrorMessage $_.Exception.Message -FunctionName "Install-ADDSDomainController"
        }
    }
}

# Common configurations for all roles
# Settings that are applied regardless of the server role, like time zone, RDP settings, and IE security configuration

# Use 'Central Standard Time'
Set-TimeZone -Name 'Central Standard Time' 

# Set RDP Settings (assuming RDP is to be enabled by default)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Set-IEEnhancedSecurityConfiguration -DisableIEEsc $true

# Additional common configurations can be placed here...

Write-Host "Configuration complete. Please review the log for details."
Write-Log "Configuration complete. Please review the log for details."
