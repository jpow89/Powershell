$repoUrl = "https://api.github.com/repos/jpow89/Powershell/contents/"
$scripts = Invoke-RestMethod -Uri $repoUrl -Headers @{ Accept = "application/vnd.github.v3+json" }
$selectedScript = $scripts | Where-Object { $_.name -like "*.ps1" } | Select-Object -ExpandProperty name | Out-GridView -Title "Select a script to run" -OutputMode Single

if ($selectedScript) {
    $scriptUrl = $scripts | Where-Object { $_.name -eq $selectedScript } | Select-Object -ExpandProperty download_url
    $scriptContent = (Invoke-WebRequest -Uri $scriptUrl).Content
    Invoke-Expression $scriptContent
}
