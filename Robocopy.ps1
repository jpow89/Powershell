# Prompt for source and destination directories
$source = Read-Host -Prompt 'Enter the source directory path'
$destination = Read-Host -Prompt 'Enter the destination directory path'

# Get all files in the source directory
$files = Get-ChildItem -Path $source -Recurse

# Use Robocopy to move the files with additional switches for robustness and logging
foreach ($file in $files) {
    robocopy $source $destination $file.Name /Z /R:5 /W:5 /COPYALL /V /LOG+:robocopy.log /TEE /MT:16
}

