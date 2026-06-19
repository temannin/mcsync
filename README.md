# mcsync

Syncs [PrismLauncher](https://prismlauncher.org/) instances from a local machine to a remote Windows PC over PowerShell Remoting (WinRM).

## How it works

1. Compresses the local instances folder into a zip archive in `$env:TEMP`
2. Prompts for credentials and opens a PSSession to the remote machine
3. Copies the archive to the remote machine's `$env:TEMP`
4. Extracts it into the remote instances folder, replacing whatever was there
5. Cleans up temp files on both ends

## Requirements

- PowerShell Remoting must be enabled on the remote machine (`Enable-PSRemoting`)
- Both machines must be on the same network or otherwise reachable by hostname

## Usage

### With `run.ps1` (recommended)

Copy `run.ps1.example` (or create `run.ps1`) with your machine-specific values and run it:

```powershell
.\run.ps1
```

`run.ps1` is gitignored so your hostnames and paths stay local.

### Directly

```powershell
.\Sync-Instances.ps1 `
    -RemoteHost "REMOTE-PC-NAME" `
    -RemoteUser "REMOTE-PC-NAME\username" `
    -LocalPath  "C:\Users\you\AppData\Roaming\PrismLauncher\instances" `
    -RemotePath "C:\Users\them\AppData\Roaming\PrismLauncher\instances"
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-RemoteHost` | Hostname or IP of the remote machine |
| `-RemoteUser` | Username for the remote machine (`HOST\user` format) |
| `-LocalPath` | Path to the PrismLauncher instances folder on this machine |
| `-RemotePath` | Path to the PrismLauncher instances folder on the remote machine |
