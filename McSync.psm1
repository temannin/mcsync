function Get-FileIndex {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Position = 1)][string[]]$TextExtensions = @(
            '.json', '.cfg', '.ini', '.toml', '.properties',
            '.txt', '.xml', '.yaml', '.yml', '.md'
        )
    )
    $index = @{}
    if (-not (Test-Path $Path)) { return $index }
    Get-ChildItem -Path $Path -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length).TrimStart('\')
        $index[$rel] = if ($TextExtensions -contains $_.Extension.ToLower()) {
            (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        } else {
            $_.Length
        }
    }
    $index
}

function Get-SyncDiff {
    param(
        [Parameter(Mandatory)][hashtable]$LocalIndex,
        [Parameter(Mandatory)][hashtable]$RemoteIndex
    )
    [PSCustomObject]@{
        ToCopy   = @($LocalIndex.Keys  | Where-Object { -not $RemoteIndex.ContainsKey($_) -or $RemoteIndex[$_] -ne $LocalIndex[$_] })
        ToDelete = @($RemoteIndex.Keys | Where-Object { -not $LocalIndex.ContainsKey($_) })
    }
}

function Get-InstanceJavaPaths {
    param(
        [Parameter(Mandatory, Position = 0)][string]$BasePath,
        [Parameter(Mandatory, Position = 1)][string[]]$CfgRelPaths
    )
    $result = @{}
    foreach ($rel in $CfgRelPaths) {
        $full = Join-Path $BasePath $rel
        if (Test-Path $full) {
            $line = Get-Content $full | Where-Object { $_ -match '^JavaPath=' } | Select-Object -First 1
            if ($line) { $result[$rel] = $line }
        }
    }
    $result
}

function Restore-InstanceJavaPaths {
    param(
        [Parameter(Mandatory, Position = 0)][string]$BasePath,
        [Parameter(Mandatory, Position = 1)]$JavaPaths
    )
    foreach ($rel in $JavaPaths.Keys) {
        $full = Join-Path $BasePath $rel
        if (-not (Test-Path $full)) { continue }
        $lines = [System.Collections.Generic.List[string]](
            Get-Content $full | Where-Object { $_ -notmatch '^JavaPath=' }
        )
        $generalIdx = $lines.IndexOf('[General]')
        if ($generalIdx -ge 0) {
            $lines.Insert($generalIdx + 1, $JavaPaths[$rel])
        } else {
            $lines.Add('[General]')
            $lines.Add($JavaPaths[$rel])
        }
        $lines | Set-Content $full
    }
}
