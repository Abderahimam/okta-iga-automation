<#
.SYNOPSIS
    Okta audit log retrieval and compliance reporting.

.DESCRIPTION
    Queries Okta System Logs for compliance events, generates CSV/JSON reports,
    and supports scheduled audit exports for SOX, GDPR, and NIST requirements.

.PARAMETER OktaDomain
    The Okta domain (e.g., company.okta.com).

.PARAMETER ApiToken
    The Okta API token for authentication.

.PARAMETER StartDate
    Start date for the audit window (ISO 8601). Defaults to 30 days ago.

.PARAMETER EndDate
    End date for the audit window. Defaults to now.

.PARAMETER EventTypes
    Comma-separated list of Okta event types to filter. Leave empty for all events.

.PARAMETER OutputPath
    Directory path for generated reports.

.PARAMETER OutputFormat
    Report format: CSV or JSON.

.EXAMPLE
    .\okta-audit-reporting.ps1 -OktaDomain "company.okta.com" -ApiToken $token -OutputPath ".\reports"

.NOTES
    Author:  Okta IGA Automation
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OktaDomain,

    [Parameter(Mandatory = $true)]
    [SecureString]$ApiToken,

    [Parameter(Mandatory = $false)]
    [datetime]$StartDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$EndDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [string[]]$EventTypes = @(),

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\reports",

    [Parameter(Mandatory = $false)]
    [ValidateSet("CSV", "JSON")]
    [string]$OutputFormat = "CSV",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs\audit-reporting.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $entry
    if (-not (Test-Path (Split-Path $LogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
    }
    Add-Content -Path $LogPath -Value $entry
}

function Get-OktaHeaders {
    param([SecureString]$Token)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    )
    return @{
        "Authorization" = "SSWS $plain"
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
    }
}

function Get-AllOktaLogs {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [datetime]$Since,
        [datetime]$Until,
        [string[]]$FilterEventTypes
    )
    $since = $Since.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
    $until = $Until.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
    $uri   = "$BaseUrl/api/v1/logs?since=$since&until=$until&limit=1000"

    if ($FilterEventTypes.Count -gt 0) {
        $filter = ($FilterEventTypes | ForEach-Object { "eventType eq `"$_`"" }) -join " or "
        $uri   += "&filter=$([uri]::EscapeDataString($filter))"
    }

    $allEvents = [System.Collections.Generic.List[object]]::new()
    Write-Log "Fetching audit logs from $since to $until ..."

    do {
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers
        if ($response) {
            $allEvents.AddRange([object[]]$response)
            Write-Log "Fetched $($allEvents.Count) events so far..."
        }
        # Follow pagination via Link header
        $nextUri = $null
        $rawResponse = Invoke-WebRequest -Method GET -Uri $uri -Headers $Headers -UseBasicParsing
        $linkHeader  = $rawResponse.Headers["Link"]
        if ($linkHeader -match '<([^>]+)>;\s*rel="next"') {
            $nextUri = $matches[1]
            $uri     = $nextUri
        }
    } while ($nextUri)

    Write-Log "Total events retrieved: $($allEvents.Count)"
    return $allEvents
}

function Convert-LogToFlatRecord {
    param([object]$Event)
    return [PSCustomObject]@{
        Published          = $Event.published
        EventType          = $Event.eventType
        DisplayMessage     = $Event.displayMessage
        Severity           = $Event.severity
        ActorId            = $Event.actor?.id
        ActorType          = $Event.actor?.type
        ActorLogin         = $Event.actor?.alternateId
        ActorDisplayName   = $Event.actor?.displayName
        ClientIpAddress    = $Event.client?.ipAddress
        ClientUserAgent    = $Event.client?.userAgent?.rawUserAgent
        ClientGeographyCity = $Event.client?.geographicalContext?.city
        ClientGeographyCountry = $Event.client?.geographicalContext?.country
        TargetId           = ($Event.target | Select-Object -First 1)?.id
        TargetType         = ($Event.target | Select-Object -First 1)?.type
        TargetLogin        = ($Event.target | Select-Object -First 1)?.alternateId
        Outcome            = $Event.outcome?.result
        OutcomeReason      = $Event.outcome?.reason
        TransactionId      = $Event.transaction?.id
        RequestId          = $Event.uuid
    }
}

function Export-AuditReport {
    param(
        [object[]]$Events,
        [string]$Format,
        [string]$ReportDir,
        [string]$ReportType = "full"
    )
    if (-not (Test-Path $ReportDir)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }

    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName   = "okta-audit-$ReportType-$timestamp"
    $flatEvents = $Events | ForEach-Object { Convert-LogToFlatRecord -Event $_ }

    switch ($Format) {
        "CSV" {
            $filePath = Join-Path $ReportDir "$fileName.csv"
            $flatEvents | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
            Write-Log "CSV report saved: $filePath"
        }
        "JSON" {
            $filePath = Join-Path $ReportDir "$fileName.json"
            $flatEvents | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8
            Write-Log "JSON report saved: $filePath"
        }
    }
    return $filePath
}

function Get-SecuritySummary {
    param([object[]]$Events)
    $failedLogins    = $Events | Where-Object { $_.eventType -eq "user.session.start" -and $_.outcome.result -eq "FAILURE" }
    $adminEvents     = $Events | Where-Object { $_.eventType -like "system.org.*" -or $_.eventType -like "user.account.privilege*" }
    $suspiciousIPs   = $failedLogins | Group-Object { $_.client.ipAddress } |
                       Where-Object { $_.Count -ge 5 } |
                       Select-Object Name, Count

    return @{
        TotalEvents          = $Events.Count
        FailedLoginAttempts  = $failedLogins.Count
        AdminActivityEvents  = $adminEvents.Count
        SuspiciousIpAddresses = $suspiciousIPs
        EventTypeSummary     = $Events | Group-Object eventType | Select-Object Name, Count | Sort-Object Count -Descending | Select-Object -First 20
    }
}

# ─── Main ────────────────────────────────────────────────────────────────────

try {
    $baseUrl = "https://$OktaDomain"
    $headers = Get-OktaHeaders -Token $ApiToken

    Write-Log "Starting audit report generation."
    Write-Log "Period: $StartDate → $EndDate"

    $events = Get-AllOktaLogs -BaseUrl $baseUrl -Headers $headers `
        -Since $StartDate -Until $EndDate -FilterEventTypes $EventTypes

    if ($events.Count -eq 0) {
        Write-Log "No events found for the specified period." "WARN"
        return
    }

    # Full report
    $reportPath = Export-AuditReport -Events $events -Format $OutputFormat `
        -ReportDir $OutputPath -ReportType "full"

    # Security summary
    $summary = Get-SecuritySummary -Events $events
    Write-Log "=== Security Summary ==="
    Write-Log "Total Events:          $($summary.TotalEvents)"
    Write-Log "Failed Login Attempts: $($summary.FailedLoginAttempts)"
    Write-Log "Admin Activity Events: $($summary.AdminActivityEvents)"

    if ($summary.SuspiciousIpAddresses.Count -gt 0) {
        Write-Log "Suspicious IPs (5+ failures):" "WARN"
        $summary.SuspiciousIpAddresses | ForEach-Object {
            Write-Log "  IP: $($_.Name) - Failures: $($_.Count)" "WARN"
        }
    }

    Write-Log "Report generation complete. Output: $reportPath"
    return $summary
}
catch {
    Write-Log "Fatal error during audit reporting: $_" "ERROR"
    throw
}
