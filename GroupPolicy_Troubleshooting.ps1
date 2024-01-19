# Auto-detect the domain name
$domainName = (Get-ADDomain).DNSRoot
$dcName = (Get-ADDomainController).HostName

# Define the output file path using $PSScriptRoot
$outputPath = Join-Path -Path $PSScriptRoot -ChildPath "GroupPolicy_Troubleshooting.txt"

# Start capturing the script output
Start-Transcript -Path $outputPath -Append

Write-Host "Domain: $domainName"
Write-Host "Domain Controller: $dcName"

# Check AD Health
Write-Host "Checking Active Directory Replication Status..."
Repadmin /showrepl
Repadmin /replsum
Repadmin /syncall

# Check DNS Health
Write-Host "Checking DNS Configuration for domain $domainName..."
Get-DnsServerResourceRecord -ZoneName $domainName

# Run DCDIAG
Write-Host "Running DCDIAG..."
dcdiag /v

# Check Group Policy Objects in the Domain
Write-Host "Checking Group Policy Objects..."
Get-GPO -All

# Check SYSVOL Share Accessibility
Write-Host "Checking SYSVOL Share Accessibility..."
$sysvolPath = "\\$dcName\SYSVOL"
Test-Path $sysvolPath

# Client-Side Troubleshooting (To be run on the client machine)
Write-Host "Client-Side Group Policy Results (Run on Client Machine)..."
gpresult /h gpresult.html

# Checking Network Connectivity to Domain Controller
Write-Host "Pinging Domain Controller $dcName..."
Test-Connection $dcName

# Check DNS resolution
Write-Host "Testing DNS Resolution for $dcName..."
Resolve-DnsName $dcName

# Stop capturing the script output
Stop-Transcript

# Final statement
Write-Host "Output saved to $outputPath"
