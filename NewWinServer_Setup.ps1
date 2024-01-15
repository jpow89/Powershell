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
        # Additional configurations as needed
    } catch {
        Write-Host "Error installing Domain Controller role: $_"
    }
}

# Function to Configure NTP Settings
function Set-NTPSettings {
    param (
        [string]$PDCName,
        [string[]]$NTPServers
    )
    try {
        $ntpServerList = $NTPServers -join ","
        Invoke-Command -ComputerName $PDCName -ScriptBlock {
            param (
                $ntpServerList
            )
            w32tm /config /manualpeerlist:$ntpServerList /syncfromflags:manual /reliable:YES /update
            Restart-Service w32time -Force
            Write-Host "NTP settings configured successfully on $using:PDCName."
        } -ArgumentList $ntpServerList
    } catch {
        Write-Host "Error configuring NTP settings on ${PDCName}: $_"
    }
}

# Main Script

# Prompt for server role
$serverRole = Read-Host "Enter Server Role (Hyper-V/DomainController)"

# Check and display current hostname
$currentHostname = [System.Net.Dns]::GetHostName()
$changeHostname = Read-Host "Current Hostname is: $currentHostname. Would you like to change it? (Yes/No)"
if ($changeHostname -eq "Yes") {
    $hostname = Read-Host "Enter New Hostname"
} else {
    $hostname = $currentHostname
}

# Conditional prompts based on server role
if ($serverRole -eq "Hyper-V") {
    $currentIP = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).IPAddress
    $currentSubnetMask = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).PrefixLength
    $currentGateway = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' }).NextHop
    $currentDNS = (Get-DnsClientServerAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).ServerAddresses

    Write-Host "Current Network Settings:"
    Write-Host "IP Address: $currentIP"
    Write-Host "Subnet Mask: $currentSubnetMask"
    Write-Host "Gateway: $currentGateway"
    Write-Host "DNS: $currentDNS"

    $ipAddress = Read-Host "Enter IP Address"
    $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
    $gateway = Read-Host "Enter Gateway"
    $dns = Read-Host "Enter DNS"
    
    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    
    # Hyper-V specific configuration calls
    Write-Log "Installing Hyper-V role..."
    Install-HyperVRole
    Write-Log "Creating external virtual switch..."
    New-ExternalVSwitch
    # Additional Hyper-V specific configurations
} elseif ($serverRole -eq "DomainController") {
    $currentIP = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).IPAddress
    $currentSubnetMask = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).PrefixLength
    $currentGateway = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' }).NextHop
    $currentDNS = (Get-DnsClientServerAddress | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }).ServerAddresses

    Write-Host "Current Network Settings:"
    Write-Host "IP Address: $currentIP"
    Write-Host "Subnet Mask: $currentSubnetMask"
    Write-Host "Gateway: $currentGateway"
    Write-Host "DNS: $currentDNS"

    $ipAddress = Read-Host "Enter IP Address"
    $subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
    $gateway = Read-Host "Enter Gateway"
    $dns = Read-Host "Enter DNS"
    
    $domainName = Read-Host "Enter Domain Name"
    $dsrmPassword = Read-Host "Enter DSRM Password"
    $siteName = Read-Host "Enter Site Name"
    $globalSubnet = Read-Host "Enter Global Subnet"
    
    $useDefaultNTP = Read-Host "Use default NTP servers? (Yes/No)"
    if ($useDefaultNTP -eq "No") {
        $ntpServers = Read-Host "Enter Comma Separated NTP Servers"
    } else {
        $ntpServers = @('0.us.pool.ntp.org', '1.us.pool.ntp.org', '2.us.pool.ntp.org', '3.us.pool.ntp.org')
    }

    $domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
    
    Write-Log "Installing Domain Controller role..."
    Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
	Write-Log "Configuring NTP settings..."
    Set-NTPSettings -PDCName $hostname -NTPServers $ntpServers
    # Additional Domain Controller specific configurations
}

# Configure Network based on role
if ($serverRole -eq "Hyper-V" -or $serverRole -eq "DomainController") {
    Set-NetworkConfiguration -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns
}

# Set RDP Settings (assuming RDP is to be enabled)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Set-IEEnhancedSecurityConfiguration -DisableIEEsc $true

# Role-specific configurations
switch ($serverRole) {
    "Hyper-V" {
        Write-Log "Starting Hyper-V configuration..."
        Install-HyperVRole
        Write-Log "Hyper-V role installed."
        Create-ExternalVSwitch
        Write-Log "External virtual switch created."
        # Additional Hyper-V specific configurations
    }
    "DomainController" {
        Write-Log "Starting Domain Controller configuration..."
        Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
        Write-Log "Domain Controller role installed."
        Configure-NTPSettings -PDCName $hostname -NTPServers $ntpServers
        Write-Log "NTP settings configured."
        # Additional Domain Controller specific configurations
    }
}

# Domain Join Logic
if ($domainJoin -eq "Yes") {
    if ($serverRole -eq "DomainController") {
        # Logic for joining the domain controller to the domain
        # This might include additional steps specific to domain controllers
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
    } else {
        # General domain join logic for other server roles
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
    }
}

# Additional script logic...
# Error handling, logging, etc.function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    # Your logging logic here
    Write-Host $Message

# Configure Network based on role
if ($serverRole -eq "Hyper-V" -or $serverRole -eq "DomainController") {
    Set-NetworkConfiguration -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns
}

# Set RDP Settings (assuming RDP is to be enabled)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Set-IEEnhancedSecurityConfiguration -DisableIEEsc $true

function Transfer-FSMORoles {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainController
    )

    # Logic for transferring FSMO roles
    # Prompt user for confirmation and perform the necessary steps
    $confirmTransfer = Read-Host "Are you sure you want to transfer the FSMO roles to $DomainController? (Yes/No)"
    if ($confirmTransfer -eq "Yes") {
        Move-ADDirectoryServerOperationMasterRole -Identity $DomainController -OperationMasterRole SchemaMaster, DomainNamingMaster, PDCEmulator, RIDMaster, InfrastructureMaster -Force
        Write-Log "FSMO roles transferred to $DomainController."
    } else {
        Write-Log "FSMO roles transfer cancelled."
    }
}

# Role-specific configurations
switch ($serverRole) {
    "Hyper-V" {
        Write-Log "Starting Hyper-V configuration..."
        Install-HyperVRole
        Write-Log "Hyper-V role installed."
        Create-ExternalVSwitch
        Write-Log "External virtual switch created."
        # Additional Hyper-V specific configurations
    }
    "DomainController" {
        Write-Log "Starting Domain Controller configuration..."
        Install-DomainControllerRole -DomainName $domainName -DSRMPassword $dsrmPassword -SiteName $siteName -GlobalSubnet $globalSubnet
        Write-Log "Domain Controller role installed."
        Configure-NTPSettings -PDCName $hostname -NTPServers $ntpServers
        Write-Log "NTP settings configured."
        # Additional Domain Controller specific configurations

        $transferFSMORoles = Read-Host "Would you like to transfer the FSMO roles to this domain controller? (Yes/No)"
        if ($transferFSMORoles -eq "Yes") {
            Transfer-FSMORoles -DomainController $hostname
        }
    }
}
# Domain Join Logic
if ($domainJoin -eq "Yes") {
    if ($serverRole -eq "DomainController") {
        # Logic for joining the domain controller to the domain
        # This might include additional steps specific to domain controllers
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
    } else {
        # General domain join logic for other server roles
        $credential = Get-Credential -Message "Enter credentials for domain join"
        Add-Computer -DomainName $domainName -Credential $credential
        Restart-Computer -Force
    }
}

# Additional script logic...
function Set-NetworkConfiguration {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IPAddress,
        [Parameter(Mandatory=$true)]
        [string]$SubnetMask,
        [Parameter(Mandatory=$true)]
        [string]$Gateway,
        [Parameter(Mandatory=$true)]
        [string]$DNS
    )

    # Logic for setting network configuration
    Set-NetIPAddress -IPAddress $IPAddress -PrefixLength $SubnetMask -DefaultGateway $Gateway
    Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter).InterfaceIndex -ServerAddresses $DNS
}

function Set-RDPSettings {
    param (
        [Parameter(Mandatory=$true)]
        [bool]$EnableRDP
    )

    # Logic for setting RDP settings
    $rdpRegistryPath = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    $rdpRegistryName = 'fDenyTSConnections'
    Set-ItemProperty -Path $rdpRegistryPath -Name $rdpRegistryName -Value (!$EnableRDP)
}

function Set-IEEnhancedSecurityConfiguration {
    param (
        [Parameter(Mandatory=$true)]
        [bool]$DisableIEEsc
    )

    # Logic for setting IE Enhanced Security Configuration
    $ieEscRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
    $ieEscRegistryName = 'IsInstalled'
    Set-ItemProperty -Path $ieEscRegistryPath -Name $ieEscRegistryName -Value (!$DisableIEEsc)
}
