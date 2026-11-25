$LogPath = "C:\Windows\Logs\ODT"
$LogFile = "$LogPath\ODT-Install.log"

if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $LogFile -Append
}

Write-Log "Starting ODT Office install"

$ODT = "$PSScriptRoot\setup.exe"
$Config = "$PSScriptRoot\config.xml"

if (-not (Test-Path $ODT)) {
    Write-Log "ERROR: setup.exe not found at $ODT"
    exit 1
}

try {
    $proc = Start-Process -FilePath $ODT -ArgumentList "/configure `"$Config`"" -Wait -PassThru -NoNewWindow
    Write-Log "ODT exit code: $($proc.ExitCode)"

    $SKU = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).ProductReleaseIds
    Write-Log "Installed SKUs: $SKU"

    exit $proc.ExitCode
}
catch {
    Write-Log "ERROR: $_"
    exit 1
}