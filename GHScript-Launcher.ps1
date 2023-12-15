$repoUrl = "https://api.github.com/repos/jpow89/Powershell/contents/"

# Use a WebClient to set the User-Agent header
$webClient = New-Object System.Net.WebClient
$webClient.Headers.Add("User-Agent", "PowerShell Script")

# Download the JSON response and convert it to an object
$jsonResponse = $webClient.DownloadString($repoUrl)
$scripts = $jsonResponse | ConvertFrom-Json

# Filter and select the script
$scriptNames = $scripts | Where-Object { $_.name -like "*.ps1" } | Select-Object -ExpandProperty name
$selectedScript = $scriptNames | Out-GridView -Title "Select a script to run" -OutputMode Single

if ($selectedScript) {
    $scriptUrl = $scripts | Where-Object { $_.name -eq $selectedScript } | Select-Object -ExpandProperty download_url
    $scriptContent = (Invoke-WebRequest -Uri $scriptUrl).Content
    Invoke-Expression $scriptContent
}
