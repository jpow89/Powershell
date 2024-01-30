# Add your variables at the top of the script
$sqlInstance = "$env:COMPUTERNAME\ADSync"
$database = 'ADSync'
$adSyncAccount = 'ASCH0\ADSyncMSA_aa83e$'

# Function to get detailed error information
function Get-DetailedErrorInfo {
    param (
        [System.Exception]$Exception
    )
    Write-Host "Error: $($Exception.Message)"
    Write-Host "Detailed Error Information: $($Exception | Format-List * | Out-String)"
}

# Function to test SQL Server status
function Test-SQLServerStatus {
    param (
        [string]$sqlInstance
    )
    try {
        $sqlService = Get-Service -ComputerName $sqlInstance -Name 'MSSQLSERVER'
        if ($sqlService.Status -eq 'Running') {
            Write-Host "SQL Server is running on $sqlInstance."
            return $true
        } else {
            Write-Host "SQL Server is not running on $sqlInstance."
            return $false
        }
    } catch {
        Get-DetailedErrorInfo -Exception $_
        return $false
    }
}

# Function to start ADSync service
function Start-ADSyncService {
    try {
        Write-Host "Attempting to start ADSync service..."
        Start-Service -Name "ADSync" -ErrorAction Stop
        Write-Host "ADSync service started successfully."
    } catch {
        Get-DetailedErrorInfo -Exception $_
    }
}

# Function to test database connectivity
function Test-DatabaseConnectivity {
    param (
        [string]$sqlInstance,
        [string]$database,
        [string]$adSyncAccount
    )
    try {
        $connectionString = "Server=$sqlInstance;Database=$database;Integrated Security=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
        $connection.Open()
        Write-Host "Successfully connected to the database $database on $sqlInstance."
        $connection.Close()
        return $true
    } catch {
        Get-DetailedErrorInfo -Exception $_
        return $false
    }
}

# Function to set database permissions
function Set-DatabasePermissions {
    param (
        [string]$sqlInstance,
        [string]$database,
        [string]$adSyncAccount
    )
    try {
        $sqlCmd = "USE $database; ALTER ROLE db_owner ADD MEMBER [$adSyncAccount];"
        $connectionString = "Server=$sqlInstance;Database=master;Integrated Security=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
        $command = New-Object System.Data.SqlClient.SqlCommand $sqlCmd, $connection
        $connection.Open()
        $command.ExecuteNonQuery()
        $connection.Close()
        Write-Host "Successfully granted db_owner role to $adSyncAccount on $database."
    } catch {
        Get-DetailedErrorInfo -Exception $_
    }
}

# Function to restart ADSync service with retries
function Restart-ADSyncService {
    param (
        [int]$retryCount = 3,
        [int]$retryIntervalSeconds = 10
    )
    $attempt = 0
    while ($attempt -lt $retryCount) {
        try {
            Start-Service -Name "ADSync" -ErrorAction Stop
            Write-Host "ADSync service started successfully."
            return $true
        } catch {
            Write-Host "Attempt $($attempt + 1) to start ADSync service failed. Retrying in $retryIntervalSeconds seconds."
            Start-Sleep -Seconds $retryIntervalSeconds
        }
        $attempt++
    }
    Write-Host "Failed to start ADSync service after $retryCount attempts."
    return $false
}

# Function to check SQL permissions
function Check-SQLPermission {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$sqlInstance,

        [Parameter(Mandatory=$true)]
        [string]$database,

        [Parameter(Mandatory=$true)]
        [string]$adSyncAccount
    )

    # Validate parameters
    if (-not $sqlInstance) { throw "SQL Instance is required." }
    if (-not $database) { throw "Database name is required." }
    if (-not $adSyncAccount) { throw "ADSync account is required." }

    # Query to check permissions
    $query = "SELECT IS_SRVROLEMEMBER('sysadmin', @adSyncAccount), IS_MEMBER('db_owner')"
    $queryParameters = @{ "adSyncAccount" = $adSyncAccount }

    try {
        # Using Integrated Security for trusted connections
        $connectionString = "Server=$sqlInstance;Database=$database;Integrated Security=True;"
        $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
        $command = New-Object System.Data.SqlClient.SqlCommand $query, $connection

        # Adding parameters to the command
        foreach ($param in $queryParameters.Keys) {
            $command.Parameters.AddWithValue($param, $queryParameters[$param])
        }

        # Execute query and process results
        $connection.Open()
        $result = $command.ExecuteScalar()
        $connection.Close()

        if ($result -eq 1) {
            Write-Host "ADSync account has necessary permissions."
        } else {
            Write-Host "ADSync account does NOT have necessary permissions."
        }
    } catch {
        Get-DetailedErrorInfo -Exception $_
    }
}

# Call the Get-ADSyncLogs function
function Get-ADSyncLogs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$logName = 'ADSync',

        [Parameter(Mandatory=$false)]
        [string]$outputPath = '',

        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 100)]
        [int]$numberOfLogs = 50
    )
}

   # Present the menu to the user
do {
    Write-Host "1. Start/Restart ADSync service"
    Write-Host "2. Get recent ADSync related logs"
    Write-Host "3. SQL checks"
    Write-Host "4. Exit"
    $input = Read-Host "Please select an option"

    switch ($input) {
        '1' { Restart-ADSyncService -retryCount 3 -retryIntervalSeconds 10 }
        '2' { Get-ADSyncLogs }
        '3' { 
            if (-not (Test-SQLServerStatus -sqlInstance $sqlInstance)) {
                Write-Host "SQL Server is not running."
            }
            elseif (-not (Test-DatabaseConnectivity -sqlInstance $sqlInstance -database $database -adSyncAccount $adSyncAccount)) {
                Write-Host "Failed to connect to the database. Attempting to set permissions..."
                Set-DatabasePermissions -sqlInstance $sqlInstance -database $database -adSyncAccount $adSyncAccount
            }
            else {
                Check-SQLPermission -sqlInstance $sqlInstance -database $database -adSyncAccount $adSyncAccount
            }
        }
        '4' { return }
        default { Write-Host "Invalid option, please try again" }
    }
} while ($true)
