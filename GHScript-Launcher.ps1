$repoUrl = "https://api.github.com/repos/jpow89/Powershell/contents/"
$headers = @{
    "User-Agent" = "PowerShell Script"
}

$scripts = Invoke-RestMethod -Uri $repoUrl -Headers $headers
$scriptNames = $scripts | Where-Object { $_.name -like "*.ps1" } | Select-Object -ExpandProperty name
$selectedScript = $scriptNames | Out-GridView -Title "Select a script to run" -OutputMode Single

if ($selectedScript) {
    $scriptUrl = $scripts | Where-Object { $_.name -eq $selectedScript } | Select-Object -ExpandProperty download_url
    $scriptContent = (Invoke-WebRequest -Uri $scriptUrl).Content
    Invoke-Expression $scriptContent
}
