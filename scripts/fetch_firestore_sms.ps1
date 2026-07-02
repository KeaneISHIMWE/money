# IMPORTANT: This file does NOT list individual SMS messages.
# It exports monthly/weekly totals stored on the user document in Firestore.
# Individual SMS bodies live in users/{phone}/transactions (not readable via REST).
# If a month looks incomplete (e.g. July shows 1 transfer but your phone had 3),
# open the app -> More -> "Refresh SMS & sync", then re-run this script.

param(
    [string]$Phone = "0792431896"
)

$ErrorActionPreference = "Stop"

function Normalize-Phone {
    param([string]$Phone)
    $n = $Phone -replace "\s+", ""
    if (-not $n.StartsWith("+")) {
        if ($n.StartsWith("0")) {
            $n = "+250" + $n.Substring(1)
        } elseif ($n.Length -eq 9) {
            $n = "+250$n"
        } else {
            $n = "+$n"
        }
    }
    return $n
}

function Local-Phone {
    param([string]$E164)
    if ($E164.StartsWith("+250") -and $E164.Length -gt 4) {
        return "0" + $E164.Substring(4)
    }
    return $E164.TrimStart("+")
}

function Encode-FirestoreDocId {
    param([string]$DocId)
    return [uri]::EscapeDataString($DocId)
}

function Parse-FirestoreValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value.PSObject.Properties.Name -contains "stringValue") { return $Value.stringValue }
    if ($Value.PSObject.Properties.Name -contains "integerValue") { return [long]$Value.integerValue }
    if ($Value.PSObject.Properties.Name -contains "doubleValue") { return [double]$Value.doubleValue }
    if ($Value.PSObject.Properties.Name -contains "booleanValue") { return $Value.booleanValue }
    if ($Value.PSObject.Properties.Name -contains "timestampValue") {
        return [DateTime]::Parse($Value.timestampValue)
    }
    if ($Value.PSObject.Properties.Name -contains "arrayValue") {
        $items = @()
        if ($Value.arrayValue.values) {
            foreach ($item in $Value.arrayValue.values) {
                $items += Parse-FirestoreValue $item
            }
        }
        return $items
    }
    if ($Value.PSObject.Properties.Name -contains "mapValue") {
        $map = @{}
        if ($Value.mapValue.fields) {
            foreach ($f in $Value.mapValue.fields.PSObject.Properties) {
                $map[$f.Name] = Parse-FirestoreValue $f.Value
            }
        }
        return $map
    }
    return $Value
}

function Parse-FirestoreDocument {
    param($Document)
    $fields = @{}
    if ($Document.fields) {
        foreach ($prop in $Document.fields.PSObject.Properties) {
            $fields[$prop.Name] = Parse-FirestoreValue $prop.Value
        }
    }
    return $fields
}

function Invoke-FirestoreRunQuery {
    param(
        [string]$ProjectId,
        [string]$ApiKey,
        [string]$ParentPath,
        [hashtable]$StructuredQuery
    )

    $encodedParent = ($ParentPath -split "/" | ForEach-Object { Encode-FirestoreDocId $_ }) -join "/"
    $url = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$encodedParent`:runQuery?key=$ApiKey"
    $body = @{ structuredQuery = $StructuredQuery } | ConvertTo-Json -Depth 20 -Compress

    $resp = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 60
    $docs = @()
    foreach ($row in @($resp)) {
        if ($row.document) {
            $docs += $row.document
        }
    }
    return $docs
}

function Get-FirestoreTransactions {
    param(
        [string]$ProjectId,
        [string]$ApiKey,
        [string]$UserDocId
    )

    $parent = "users/$UserDocId"
    $allDocs = @()
    $lastDate = $null
    $pageSize = 300

    while ($true) {
        $query = @{
            from = @(@{ collectionId = "transactions" })
            orderBy = @(@{
                field = @{ fieldPath = "date" }
                direction = "DESCENDING"
            })
            limit = $pageSize
        }

        if ($null -ne $lastDate) {
            $query.where = @{
                fieldFilter = @{
                    field = @{ fieldPath = "date" }
                    op = "LESS_THAN"
                    value = @{ timestampValue = $lastDate.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'") }
                }
            }
        }

        $page = Invoke-FirestoreRunQuery -ProjectId $ProjectId -ApiKey $ApiKey -ParentPath $parent -StructuredQuery $query
        if ($page.Count -eq 0) { break }

        $allDocs += $page

        $lastFields = Parse-FirestoreDocument $page[-1]
        $lastDate = $lastFields["date"]
        if (-not ($lastDate -is [DateTime])) { break }
        if ($page.Count -lt $pageSize) { break }
    }

    return $allDocs
}

function Format-SummaryTable {
    param(
        [string]$Title,
        [array]$Rows,
        [string]$DateField
    )

    $lines = @("=== $Title ===")
    if ($Rows.Count -eq 0) {
        $lines += "(none)"
        return $lines
    }

    foreach ($row in $Rows) {
        $when = $row[$DateField]
        $label = if ($when -is [DateTime]) { $when.ToString("yyyy-MM-dd") } else { [string]$when }
        $received = [math]::Round([double]$row["totalReceived"], 0)
        $sent = [math]::Round([double]$row["totalSent"], 0)
        $count = [int]$row["transactionCount"]
        $lines += "$label | received: $received RWF | sent: $sent RWF | count: $count"
    }
    return $lines
}

$projectId = "money-dashboard-2026"
$apiKey = "AIzaSyAvVcp2ejSDBa5xMU-VU8W7vBscHSQKM0s"
$e164 = Normalize-Phone $Phone
$local = Local-Phone $e164
$outFile = Join-Path $PSScriptRoot "..\data\sms_$local.txt"
$outDir = Split-Path $outFile -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Host "Fetching Firestore data for $e164 ..."

$userDoc = $null
$userFields = @{}
$txAccess = "unknown"
$docs = @()

try {
    $userUrl = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/users/$(Encode-FirestoreDocId $e164)?key=$apiKey"
    $userDoc = Invoke-RestMethod -Uri $userUrl -Method Get -TimeoutSec 30
    $userFields = Parse-FirestoreDocument $userDoc
} catch {
    Write-Warning "User document not found or not accessible: $e164"
}

try {
    $docs = Get-FirestoreTransactions -ProjectId $projectId -ApiKey $apiKey -UserDocId $e164
    $txAccess = "allowed"
} catch {
    $txAccess = "forbidden"
    Write-Warning "Could not read transactions subcollection: $($_.Exception.Message)"
}

$lines = @(
    "# Firestore export for $local",
    "# User: users/$e164",
    "# Generated: $(Get-Date -Format o)",
    "# Transactions readable: $(if ($txAccess -eq 'allowed') { $docs.Count } else { 'no (403 Forbidden)' })",
    ""
)

if ($userFields.Count -gt 0) {
    $lines += "=== USER PROFILE ==="
    foreach ($key in @("name", "phone", "isPublic", "createdAt", "lastDashboardUpdate", "lastPublicUpdate")) {
        if ($userFields.ContainsKey($key)) {
            $val = $userFields[$key]
            if ($val -is [DateTime]) { $val = $val.ToString("o") }
            $lines += "$key`: $val"
        }
    }
    $lines += ""

    $dashboard = @($userFields["dashboardSummaries"])
    $publicMonthly = @($userFields["publicSummaries"])
    $publicWeekly = @($userFields["publicWeeklySummaries"])

    $lines += Format-SummaryTable -Title "DASHBOARD SUMMARIES (private monthly aggregates)" -Rows $dashboard -DateField "month"
    $lines += ""
    $lines += Format-SummaryTable -Title "PUBLIC MONTHLY SUMMARIES" -Rows $publicMonthly -DateField "month"
    $lines += ""
    $lines += Format-SummaryTable -Title "PUBLIC WEEKLY SUMMARIES" -Rows $publicWeekly -DateField "weekStart"
    $lines += ""

    $totalCount = ($dashboard | ForEach-Object { [int]$_.transactionCount } | Measure-Object -Sum).Sum
    $lines += "Total transactions represented in dashboard summaries: $totalCount"
    $lines += ""
}

foreach ($doc in $docs) {
    $fields = Parse-FirestoreDocument $doc
    $docId = ($doc.name -split "/")[-1]
    $date = $fields["date"]
    $when = if ($date -is [DateTime]) { $date.ToString("yyyy-MM-dd HH:mm:ss") } else { "unknown-date" }

    $lines += "----------------------------------------"
    $lines += "Doc ID:         $docId"
    $lines += "Date:           $when"
    $lines += "Type:           $($fields['type'])"
    $lines += "Amount:         $($fields['amount']) RWF"
    $lines += "Counterparty:   $($fields['counterparty'])"
    $lines += "Category:       $($fields['category'])"
    $lines += "Transaction ID: $($fields['transactionId'])"
    $lines += "Balance:        $($fields['balance'])"
    $lines += "Fee:            $($fields['fee'])"
    $lines += "Source:         $($fields['source'])"
    $lines += "SMS body:"
    $lines += [string]$fields["description"]
    $lines += ""
}

if ($docs.Count -eq 0) {
    $lines += "=== INDIVIDUAL SMS / TRANSACTIONS ==="
    $lines += "No transaction documents could be read from Firestore."
    $lines += ""
    $lines += "Firestore stores raw SMS text in:"
    $lines += "  users/$e164/transactions/{docId}.description"
    $lines += ""
    $lines += "The REST API returned 403 Forbidden for that subcollection."
    $lines += "Only monthly/weekly aggregates are stored on the user document (exported above)."
    $lines += ""
    $lines += "To export individual SMS bodies you can:"
    $lines += "  1. Use the app More tab -> Export SMS (reads device SMS inbox)"
    $lines += "  2. Temporarily relax Firestore rules and re-run this script"
    $lines += "  3. Export via Firebase Console or a service account with admin access"
}

$lines | Set-Content -Path $outFile -Encoding UTF8
Write-Host "Wrote export to $outFile"
