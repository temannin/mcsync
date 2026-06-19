param(
    [Parameter(Mandatory)][string]$RemoteHost,
    [Parameter(Mandatory)][string]$RemoteUser,
    [Parameter(Mandatory)][string]$LocalPath,
    [Parameter(Mandatory)][string]$RemotePath
)

$zip = "$env:TEMP\prism-instances.zip"

Write-Host "Compressing instances..."
Compress-Archive -Path "$LocalPath\*" -DestinationPath $zip -Force

$cred      = Get-Credential -UserName $RemoteUser -Message "Enter password for $RemoteUser"
$session   = New-PSSession -ComputerName $RemoteHost -Credential $cred
$remoteZip = (Invoke-Command -Session $session -ScriptBlock { "$env:TEMP\prism-instances.zip" })

try {
    Write-Host "Copying archive to $RemoteHost..."
    Copy-Item -Path $zip -Destination $remoteZip -ToSession $session -Force

    Write-Host "Extracting on $RemoteHost..."
    Invoke-Command -Session $session -ScriptBlock {
        param($src, $dest)
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Expand-Archive -Path $src -DestinationPath $dest -Force
        Remove-Item $src -Force
    } -ArgumentList $remoteZip, $RemotePath
} finally {
    Remove-PSSession $session
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
}

Write-Host "Done."
