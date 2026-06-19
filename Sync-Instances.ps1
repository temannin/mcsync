param(
    [Parameter(Mandatory)][string]$RemoteHost,
    [Parameter(Mandatory)][string]$RemoteUser,
    [Parameter(Mandatory)][string]$LocalPath,
    [Parameter(Mandatory)][string]$RemotePath,
    [switch]$DryRun
)

$textExts = @('.json', '.cfg', '.ini', '.toml', '.properties', '.txt', '.xml', '.yaml', '.yml', '.md')
$log      = "$PSScriptRoot\sync.log"
function Log($msg) { $msg | Add-Content $log }

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]$(if ($DryRun) { ' [DryRun]' })" | Set-Content $log

$cred    = Get-Credential -UserName $RemoteUser -Message "Enter password for $RemoteUser"
$session = New-PSSession -ComputerName $RemoteHost -Credential $cred

try {
    Log "Indexing local files..."
    $localIndex = @{}
    $localSizes = @{}
    Get-ChildItem -Path $LocalPath -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($LocalPath.Length).TrimStart('\')
        $localSizes[$rel] = $_.Length
        $localIndex[$rel] = if ($textExts -contains $_.Extension.ToLower()) {
            (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        } else {
            $_.Length
        }
    }

    Log "Indexing remote files..."
    $remoteIndex = Invoke-Command -Session $session -ScriptBlock {
        param($path)
        $index = @{}
        if (Test-Path $path) {
            Get-ChildItem -Path $path -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($path.Length).TrimStart('\')
                $index[$rel] = if ($using:textExts -contains $_.Extension.ToLower()) {
                    (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                } else {
                    $_.Length
                }
            }
        }
        $index
    } -ArgumentList $RemotePath

    $toCopy   = @($localIndex.Keys  | Where-Object { -not $remoteIndex.ContainsKey($_) -or $remoteIndex[$_] -ne $localIndex[$_] })
    $toDelete = @($remoteIndex.Keys | Where-Object { -not $localIndex.ContainsKey($_) })

    $totalMB = [math]::Round(($toCopy | ForEach-Object { $localSizes[$_] } | Measure-Object -Sum).Sum / 1MB, 2)
    Log "$($toCopy.Count) file(s) to copy ($totalMB MB), $($toDelete.Count) to remove."
    $toCopy   | ForEach-Object { Log "  + $_" }
    $toDelete | ForEach-Object { Log "  - $_" }

    if ($DryRun) { return }

    if ($toCopy.Count -gt 0) {
        $stageDir = Join-Path $env:TEMP "mcsync_$(Get-Random)"
        $zipPath  = "$stageDir.zip"
        try {
            foreach ($rel in $toCopy) {
                $stageFile   = Join-Path $stageDir $rel
                $stageParent = Split-Path $stageFile
                if (-not (Test-Path $stageParent)) {
                    New-Item -ItemType Directory -Path $stageParent -Force | Out-Null
                }
                Copy-Item -Path (Join-Path $LocalPath $rel) -Destination $stageFile
            }

            Log "Compressing $($toCopy.Count) file(s)..."
            Compress-Archive -Path "$stageDir\*" -DestinationPath $zipPath -Force

            Log "Transferring archive..."
            $remoteTmp = Invoke-Command -Session $session -ScriptBlock { $env:TEMP }
            $remoteZip = Join-Path $remoteTmp "_mcsync.zip"
            Copy-Item -Path $zipPath -Destination $remoteZip -ToSession $session -Force

            $instanceCfgs = @($toCopy | Where-Object { (Split-Path $_ -Leaf) -eq 'instance.cfg' })
            $remoteJavaPaths = @{}
            if ($instanceCfgs.Count -gt 0) {
                $remoteJavaPaths = Invoke-Command -Session $session -ScriptBlock {
                    param($path, $rels)
                    $result = @{}
                    foreach ($rel in $rels) {
                        $full = Join-Path $path $rel
                        if (Test-Path $full) {
                            $line = Get-Content $full | Where-Object { $_ -match '^JavaPath=' } | Select-Object -First 1
                            if ($line) { $result[$rel] = $line }
                        }
                    }
                    $result
                } -ArgumentList $RemotePath, $instanceCfgs
            }

            Log "Extracting on remote..."
            Invoke-Command -Session $session -ScriptBlock {
                param($src, $dest)
                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Expand-Archive -Path $src -DestinationPath $dest -Force
                Remove-Item $src -Force
            } -ArgumentList $remoteZip, $RemotePath

            if ($remoteJavaPaths.Count -gt 0) {
                Invoke-Command -Session $session -ScriptBlock {
                    param($path, $javaPaths)
                    foreach ($rel in $javaPaths.Keys) {
                        $full = Join-Path $path $rel
                        if (Test-Path $full) {
                            $lines = [System.Collections.Generic.List[string]](Get-Content $full | Where-Object { $_ -notmatch '^JavaPath=' })
                            $generalIdx = $lines.IndexOf('[General]')
                            if ($generalIdx -ge 0) {
                                $lines.Insert($generalIdx + 1, $javaPaths[$rel])
                            } else {
                                $lines.Add('[General]')
                                $lines.Add($javaPaths[$rel])
                            }
                            $lines | Set-Content $full
                        }
                    }
                } -ArgumentList $RemotePath, $remoteJavaPaths
            }
        } finally {
            Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $zipPath  -Force          -ErrorAction SilentlyContinue
        }
    }

    if ($toDelete.Count -gt 0) {
        $remoteToDelete = @($toDelete | ForEach-Object { Join-Path $RemotePath $_ })
        Invoke-Command -Session $session -ScriptBlock {
            param($files)
            foreach ($f in $files) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        } -ArgumentList (,$remoteToDelete)
    }
} finally {
    Remove-PSSession $session
}

Log "Done."
