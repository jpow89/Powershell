# Check if winget is available
try {
    winget --version
    Write-Host "winget is already installed."
} catch {
    Write-Host "winget not found. Attempting to install..."
    InstallWinGet
}

function InstallWinGet {
    $hasPackageManager = Get-AppPackage -Name "Microsoft.DesktopAppInstaller"

    if (!$hasPackageManager) {
        try {
            # Download and install the App Installer package
            Add-AppxPackage -Path "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"

            $releases_url = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $releases = Invoke-RestMethod -Uri $releases_url
            $latestRelease = $releases.assets | Where-Object { $_.browser_download_url.EndsWith("msixbundle") } | Select-Object -First 1

            Add-AppxPackage -Path $latestRelease.browser_download_url
            Write-Host "winget installed successfully."
        } catch {
            Write-Host "Error installing winget. Please check your internet connection and try again."
        }
    } else {
        Write-Host "App Installer is already installed."
    }
}

# Install Python using winget
try {
    winget install Python.Python --silent --accept-package-agreements --accept-source-agreements
    Write-Host "Python installed successfully."

    # Set Python environment path (adjust as needed)
    $pythonPath = "C:\Python"
    [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";$pythonPath", [EnvironmentVariableTarget]::Machine)
    
    # Install required Python packages
    pip install numpy matplotlib sounddevice

    Write-Host "Required Python packages installed successfully."
} catch {
    Write-Host "Error installing Python or Python packages."
}
