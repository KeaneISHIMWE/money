# Exports SMS from a connected Android device via adb.
# Usage: .\scripts\export_sms.ps1 -Phone "0792431896"

param(
    [string]$Phone = "0792431896",
    [string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    throw "adb not found at $adb. Install Android SDK platform-tools."
}

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }
if (-not $devices) {
    throw @"
No Android device detected.
1. Enable Developer options + USB debugging on the phone.
2. Connect the phone with USB and accept the debugging prompt.
3. Run this script again.
"@
}

$digits = $Phone -replace "\D", ""
if ($digits.StartsWith("0")) {
    $digits = $digits.Substring(1)
}
$local = "0$digits"
$intl = "+250$digits"

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $PSScriptRoot "..\data\sms_$local.txt"
}

$outDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

function Parse-AdbSmsRows {
    param([string]$Raw)
    $messages = @()
    $current = @{}

    foreach ($line in ($Raw -split "`n")) {
        $line = $line.Trim()
        if ($line -match "^Row:\s*(\d+)\s+(.*)$") {
            if ($current.Count -gt 0) {
                $messages += [pscustomobject]$current
            }
            $current = @{}
            $rest = $Matches[2]
            if ($rest -match "^(\w+)=(.*)$") {
                $current[$Matches[1]] = $Matches[2]
            }
            continue
        }
        if ($line -match "^(\w+)=(.*)$") {
            $current[$Matches[1]] = $Matches[2]
        }
    }
    if ($current.Count -gt 0) {
        $messages += [pscustomobject]$current
    }
    return $messages
}

$uris = @(
    "content://sms/inbox",
    "content://sms/sent"
)

$all = @()
foreach ($uri in $uris) {
    $raw = & $adb shell content query --uri $uri `
        --projection _id,address,body,date,type,read 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        continue
    }
    $parsed = Parse-AdbSmsRows $raw
    foreach ($msg in $parsed) {
        $all += $msg
    }
}

$patterns = @(
    $local,
    $intl,
    $digits,
    "250$digits"
)

$filtered = $all | Where-Object {
    $address = [string]$_.address
    $body = [string]$_.body
    $addressMatch = $false
    $bodyMatch = $false
    foreach ($p in $patterns) {
        if ($address -like "*$p*") { $addressMatch = $true }
        if ($body -like "*$p*") { $bodyMatch = $true }
    }
    $addressMatch -or $bodyMatch -or ($address -eq "M-Money")
} | Sort-Object { [int64]$_.date } -Descending

$lines = @(
    "# SMS export for $local",
    "# Generated: $(Get-Date -Format o)",
    "# Device messages matched: $($filtered.Count) / $($all.Count) total scanned",
    ""
)

foreach ($msg in $filtered) {
    $epochMs = [int64]$msg.date
    if ($epochMs -gt 0) {
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($epochMs).LocalDateTime
        $when = $dt.ToString("yyyy-MM-dd HH:mm:ss")
    } else {
        $when = "unknown-date"
    }
    $lines += "----------------------------------------"
    $lines += "Date:   $when"
    $lines += "From:   $($msg.address)"
    $lines += "Type:   $($msg.type)"
    $lines += "Body:"
    $lines += [string]$msg.body
    $lines += ""
}

$lines | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Wrote $($filtered.Count) messages to $OutputFile"
