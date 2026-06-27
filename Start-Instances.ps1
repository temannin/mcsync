param(
    [string]$Instance
)

$prism = "$env:LOCALAPPDATA\Programs\PrismLauncher\prismlauncher.exe"
$instancesPath = "$env:APPDATA\PrismLauncher\instances"

if (-not (Test-Path $prism)) {
    Write-Error "PrismLauncher not found at: $prism"
    exit 1
}

if (-not $Instance) {
    if (-not (Test-Path $instancesPath)) {
        Write-Error "Instances folder not found at: $instancesPath"
        exit 1
    }

    $names = @(Get-ChildItem -Path $instancesPath -Directory | ForEach-Object {
            $cfg = Join-Path $_.FullName "instance.cfg"
            if (Test-Path $cfg) {
                $line = Get-Content $cfg | Where-Object { $_ -match '^name=' } | Select-Object -First 1
                if ($line) { $line.Substring(5) } else { $_.Name }
            }
            else {
                $_.Name
            }
        })

    if ($names.Count -eq 0) {
        Write-Error "No instances found in: $instancesPath"
        exit 1
    }

    Write-Host "Available instances:"
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host "  [$($i + 1)] $($names[$i])"
    }

    $choice = Read-Host "Select an instance (1-$($names.Count))"
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $names.Count) {
        Write-Error "Invalid selection: $choice"
        exit 1
    }

    $Instance = $names[$idx]
}

Write-Host "Launching: $Instance"
Start-Process -FilePath $prism -ArgumentList "--launch `"$Instance`""
