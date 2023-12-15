$repoUrl = "https://api.github.com/repos/jpow89/Powershell/contents/"
$webRequest = [System.Net.WebRequest]::Create($repoUrl)
$webRequest.Headers.Add("User-Agent", "PowerShell Script")
$response = $webRequest.GetResponse()
$reader = New-Object System.IO.StreamReader($response.GetResponseStream())
$json = $reader.ReadToEnd() | ConvertFrom-Json
$response.Close()

$scripts = $json | Where-Object { $_.name -like "*.ps1" }
$selectedScript = $scripts | Select-Object -ExpandProperty name | Out-GridView -Title "Select a script to run" -OutputMode Single

if ($selectedScript) {
    $scriptUrl = $scripts | Where-Object { $_.name -eq $selectedScript } | Select-Object -ExpandProperty download_url
    $scriptContent = (Invoke-WebRequest -Uri $scriptUrl).Content
    Invoke-Expression $scriptContent
}

