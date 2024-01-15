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

# Function to Transfer FSMO Roles
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

# Main Script Logic

# Prompt for server role
$serverRole = Read-Host "Enter Server Role (Hyper-V/DomainController)"

# Conditional prompts based on server role
switch ($serverRole) {
    "Hyper-V" {
        # Hyper-V specific logic...
    }
    "DomainController" {
        # Domain Controller specific logic...
    }
    default {
        Write-Host "Invalid server role selected."
    }
}

# Common network configuration for all roles
$ipAddress = Read-Host "Enter IP Address"
$subnetMask = Read-Host "Enter Subnet Mask (as prefix length, e.g., 24)"
$gateway = Read-Host "Enter Gateway"
$dns = Read-Host "Enter DNS"

# Apply network configuration
Set-NetworkConfiguration -IPAddress $ipAddress -SubnetMask $subnetMask -Gateway $gateway -DNS $dns

# Domain Join Logic
$domainJoin = Read-Host "Would you like to join this server to a domain? (Yes/No)"
if ($domainJoin -eq "Yes") {
    $credential = Get-Credential -Message "Enter credentials for domain join"
    Add-Computer -DomainName $domainName -Credential $credential
    Restart-Computer -Force
    Write-Log "Server joined to the domain and restarted."
} else {
    Write-Log "Server not joined to any domain."
}

# Set RDP Settings (assuming RDP is to be enabled by default)
Set-RDPSettings -EnableRDP $true

# Disable IE Enhanced Security Configuration
Set-IEEnhancedSecurityConfiguration -DisableIEEsc $true

# Additional common configurations can be placed here...

Write-Host "Configuration complete. Please review the log for details."
