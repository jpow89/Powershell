<#
.SYNOPSIS
This script downloads and installs Bitdefender on a customer's system using data from a CSV file hosted on GitHub.

.DESCRIPTION
Using provided GitHub token and URL, the script downloads a CSV file containing customer data, allows the user to select a company, and then downloads and installs Bitdefender for that company.

.NOTES
Requires modifications and checks before running in a production environment.
#>

Enum LogLevel {
    ERROR
    WARN
    INFO
    DEBUG
}

# Script-wide variables for logging
$Script:Verbosity = [LogLevel]::INFO
$Script:LogFilePath = "$env:TEMP\Bitdefender_Install.log"

# Function to write entries to the Windows Event Log (ensure the source exists or create it)
Function Write-EventLogEntry {
    Param (
        [string]$Message,
        [string]$EventId = 1000,  # Default Event ID
        [System.Diagnostics.EventLogEntryType]$EntryType = [System.Diagnostics.EventLogEntryType]::Information
    )
    if ($Script:Verbosity -ge [LogLevel]::DEBUG) {
        # Ensure the source exists, if not, attempt to create it (requires admin privileges)
        $source = "BitdefenderScript"
        if (![System.Diagnostics.EventLog]::SourceExists($source)) {
            # Creating the source requires admin rights and typically a system restart
            [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
        }

        Write-EventLog -LogName Application -Source $source -EntryType $EntryType -EventId $EventId -Message $Message
    }
}

# Logging function to write messages based on the verbosity level
Function Write-Log {
    Param (
        [string]$Message,
        [LogLevel]$Level = [LogLevel]::INFO
    )
    if ($Script:Verbosity -ge $Level) {
        "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) [$Level]: $Message" | Out-File -FilePath $Script:LogFilePath -Append
    }
}

# Function to initialize verbosity level from user input
Function Initialize-VerboseMode {
    Write-Host "Select Verbosity Level:"
    Write-Host "1. Standard"
    Write-Host "2. Enhanced Verbose Mode"
    $choice = Read-Host "Enter choice (1-2)"
    switch ($choice) {
        "2" { $Script:Verbosity = [LogLevel]::DEBUG }
        Default { $Script:Verbosity = [LogLevel]::INFO }
    }
    Write-Log "Verbosity set to $Script:Verbosity" -Level DEBUG
}

Initialize-VerboseMode

# Function to get customer data from the CSV
Function Get-CustomerData {
    param (
        [string]$CsvUrl,
        [string]$Token
    )
    $csvTempPath = "$env:TEMP\BitdefenderURL.csv"
    $headers = @{
        "Authorization" = "token $Token"
        "Accept" = "application/vnd.github.v3.raw"
    }
    $webClient = New-Object System.Net.WebClient
    foreach ($key in $headers.Keys) {
        $webClient.Headers.Add($key, $headers[$key])
    }

    try {
        $webClient.DownloadFile($CsvUrl, $csvTempPath)
        Write-Log "Successfully downloaded customer data CSV to $csvTempPath" -Level INFO
        return Import-Csv -Path $csvTempPath
    }
    catch {
        Write-Log "Failed to download or parse the CSV. Error: $_. Exception: $($_.Exception.Message)" -Level ERROR
        Exit 1
    }
}

# Function to download files
Function New-FileDownload {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )
    $webClient = New-Object System.Net.WebClient
    try {
        $webClient.DownloadFile($Url, $Destination)
        Write-Log "File downloaded successfully to $Destination" -Level INFO
        return $true
    }
    catch {
        Write-Log "File download Failed: $_. Exception: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# Main script and functions follow with try-catch blocks for error handling
try {
    # Customer data retrieval and selection logic
    $GithubToken = Read-Host "Enter your GitHub Token"
    $CsvUrl = "https://raw.githubusercontent.com/jpow89/Powershell_Private/main/BitdefenderURL.csv?token=GHSAT0AAAAAACJ4FYYYG7VFNIM4YEOUNDNQZMUP7HA"
    $customerData = Get-CustomerData -CsvUrl $CsvUrl -Token $GithubToken

    Write-Host "Please select a company from the following list:"
    $index = 0
    $customerData | Sort-Object Company | ForEach-Object {
        Write-Host "$index. $($_.Company)"
        $index++
    }

    $selected = Read-Host "Enter the number corresponding to the company"
    $selectedCompany = $customerData[$selected]

    if ([string]::IsNullOrWhiteSpace($selectedCompany.BitdefenderURL)) {
        Write-Log "No BitdefenderURL found for $($selectedCompany.Company)" -Level WARN
        Exit
    } else {
        $BitdefenderURL = $selectedCompany.BitdefenderURL
    }

    # Define the file paths
    $Destination = "$($env:TEMP)\$($BitdefenderURL)"

    # Check if Bitdefender is already installed
    $Installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
    Where-Object { $_.DisplayName -eq "Bitdefender Endpoint Security Tools" }

    if ($Installed) {
        Write-Log "Bitdefender already installed for $($selectedCompany.Company). Exiting." -Level INFO
        Exit 1
    }

    # Download and install Bitdefender
    $BaseURL = "https://cloud.gravityzone.bitdefender.com/Packages/BSTWIN/0/"
    $URL = $BaseURL + $BitdefenderURL

    $FileDownload = New-FileDownload -Url $URL -Destination $Destination
    if ($FileDownload) {
        Write-Log "Beginning installation for $($selectedCompany.Company)..." -Level INFO
        Start-Process $Destination -ArgumentList "/bdparams /silent" -Wait -NoNewWindow

        # Recheck Bitdefender installation
        $Installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
        Where-Object { $_.DisplayName -eq "Bitdefender Endpoint Security Tools" }
        if ($Installed) {
            Write-Log "Bitdefender successfully installed for $($selectedCompany.Company)." -Level INFO
        } else {
            Write-Log "ERROR: Failed to install Bitdefender for $($selectedCompany.Company)" -Level ERROR
        }
    } else {
        Write-Log "File failed to download for $($selectedCompany.Company). Exiting." -Level ERROR
        Exit 1
    }
}
catch {
    Write-Log "An unexpected error occurred: $_" -Level ERROR
    # Optionally add more detailed error information in debug mode
    if ($Script:Verbosity -eq [LogLevel]::DEBUG) {
        $_ | Out-String | Write-Log -Level DEBUG
    }
}
finally {
    # Clean up resources, stop transcripts, etc.
    Write-Log "Script execution completed" -Level INFO
}

# Final log entry indicating script completion
Write-Log "Script completed" -Level INFO
