<#
.SYNOPSIS
    Access request workflow automation for Okta.

.DESCRIPTION
    Automates access request processing including group membership management,
    application assignments, approval workflows, and access certification.

.PARAMETER Action
    Action: RequestAccess, RevokeAccess, ApproveRequest, DenyRequest, ListPendingRequests.

.PARAMETER OktaDomain
    The Okta domain.

.PARAMETER ApiToken
    The Okta API token.

.EXAMPLE
    .\access-request-automation.ps1 -Action RequestAccess -OktaDomain "company.okta.com" -ApiToken $token `
        -UserId "00u1abc" -ResourceId "00g2xyz" -ResourceType "Group"

.NOTES
    Author:  Okta IGA Automation
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("RequestAccess", "RevokeAccess", "ApproveRequest", "DenyRequest", "ListPendingRequests", "BulkProvision", "BulkDeprovision")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$OktaDomain,

    [Parameter(Mandatory = $true)]
    [SecureString]$ApiToken,

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Group", "Application")]
    [string]$ResourceType = "Group",

    [Parameter(Mandatory = $false)]
    [string]$Justification,

    [Parameter(Mandatory = $false)]
    [string[]]$UserIds = @(),

    [Parameter(Mandatory = $false)]
    [string]$RequestDbPath = ".\data\access-requests.json",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs\access-request.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $entry
    foreach ($path in @($LogPath, $RequestDbPath)) {
        $dir = Split-Path $path
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Add-Content -Path $LogPath -Value $entry
}

function Get-OktaHeaders {
    param([SecureString]$Token)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    )
    return @{ "Authorization" = "SSWS $plain"; "Accept" = "application/json"; "Content-Type" = "application/json" }
}

function Invoke-OktaApi {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body = $null)
    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ContentType = "application/json" }
    if ($Body) { $params["Body"] = $Body }
    return Invoke-RestMethod @params
}

# ─── Access Request Store (file-backed, replace with DB in production) ────────

function Get-RequestStore {
    if (Test-Path $RequestDbPath) {
        return Get-Content $RequestDbPath -Raw | ConvertFrom-Json -AsHashtable
    }
    return @{ requests = @() }
}

function Save-RequestStore {
    param([hashtable]$Store)
    $Store | ConvertTo-Json -Depth 10 | Set-Content $RequestDbPath -Encoding UTF8
}

function New-AccessRequest {
    param([string]$ReqUserId, [string]$ReqResourceId, [string]$ReqResourceType, [string]$ReqJustification)
    $store = Get-RequestStore
    $request = @{
        id           = [guid]::NewGuid().ToString()
        userId       = $ReqUserId
        resourceId   = $ReqResourceId
        resourceType = $ReqResourceType
        justification = $ReqJustification
        status       = "PENDING"
        createdAt    = (Get-Date -Format "o")
        updatedAt    = (Get-Date -Format "o")
    }
    if (-not $store.requests) { $store.requests = @() }
    $store.requests += $request
    Save-RequestStore -Store $store
    Write-Log "Access request created. ID: $($request.id)"
    return $request
}

function Get-PendingRequests {
    $store = Get-RequestStore
    return $store.requests | Where-Object { $_.status -eq "PENDING" }
}

# ─── Okta Group / App Assignment ─────────────────────────────────────────────

function Add-UserToGroup {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$OktaGroupId)
    Write-Log "Adding user $OktaUserId to group $OktaGroupId"
    $uri = "$BaseUrl/api/v1/groups/$OktaGroupId/users/$OktaUserId"
    Invoke-OktaApi -Method PUT -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId added to group $OktaGroupId."
}

function Remove-UserFromGroup {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$OktaGroupId)
    Write-Log "Removing user $OktaUserId from group $OktaGroupId"
    $uri = "$BaseUrl/api/v1/groups/$OktaGroupId/users/$OktaUserId"
    Invoke-OktaApi -Method DELETE -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId removed from group $OktaGroupId."
}

function Add-UserToApp {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$AppId)
    Write-Log "Assigning user $OktaUserId to application $AppId"
    $body = @{ id = $OktaUserId; scope = "USER" } | ConvertTo-Json
    $uri  = "$BaseUrl/api/v1/apps/$AppId/users"
    $result = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers -Body $body
    Write-Log "User $OktaUserId assigned to app $AppId."
    return $result
}

function Remove-UserFromApp {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$AppId)
    Write-Log "Removing user $OktaUserId from application $AppId"
    $uri = "$BaseUrl/api/v1/apps/$AppId/users/$OktaUserId"
    Invoke-OktaApi -Method DELETE -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId removed from app $AppId."
}

function Grant-Access {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$OktaResourceId, [string]$OktaResourceType)
    if ($OktaResourceType -eq "Group") {
        Add-UserToGroup -BaseUrl $BaseUrl -Headers $Headers -OktaUserId $OktaUserId -OktaGroupId $OktaResourceId
    }
    else {
        Add-UserToApp -BaseUrl $BaseUrl -Headers $Headers -OktaUserId $OktaUserId -AppId $OktaResourceId
    }
}

function Revoke-Access {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaUserId, [string]$OktaResourceId, [string]$OktaResourceType)
    if ($OktaResourceType -eq "Group") {
        Remove-UserFromGroup -BaseUrl $BaseUrl -Headers $Headers -OktaUserId $OktaUserId -OktaGroupId $OktaResourceId
    }
    else {
        Remove-UserFromApp -BaseUrl $BaseUrl -Headers $Headers -OktaUserId $OktaUserId -AppId $OktaResourceId
    }
}

# ─── Main ────────────────────────────────────────────────────────────────────

try {
    $baseUrl = "https://$OktaDomain"
    $headers = Get-OktaHeaders -Token $ApiToken

    Write-Log "Action: $Action"

    switch ($Action) {
        "RequestAccess" {
            if (-not $UserId -or -not $ResourceId) { throw "UserId and ResourceId are required." }
            return New-AccessRequest -ReqUserId $UserId -ReqResourceId $ResourceId `
                -ReqResourceType $ResourceType -ReqJustification $Justification
        }
        "ApproveRequest" {
            if (-not $UserId -or -not $ResourceId) { throw "UserId and ResourceId required for approval." }
            if ($PSCmdlet.ShouldProcess($UserId, "Grant $ResourceType access")) {
                Grant-Access -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId `
                    -OktaResourceId $ResourceId -OktaResourceType $ResourceType
            }
        }
        "RevokeAccess" {
            if (-not $UserId -or -not $ResourceId) { throw "UserId and ResourceId required for revocation." }
            if ($PSCmdlet.ShouldProcess($UserId, "Revoke $ResourceType access")) {
                Revoke-Access -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId `
                    -OktaResourceId $ResourceId -OktaResourceType $ResourceType
            }
        }
        "DenyRequest"         { Write-Log "Request denied for user: $UserId" "WARN" }
        "ListPendingRequests" { return Get-PendingRequests }
        "BulkProvision" {
            if ($UserIds.Count -eq 0 -or -not $ResourceId) { throw "UserIds and ResourceId required." }
            foreach ($uid in $UserIds) {
                if ($PSCmdlet.ShouldProcess($uid, "Bulk provision to $ResourceType")) {
                    Grant-Access -BaseUrl $baseUrl -Headers $headers -OktaUserId $uid `
                        -OktaResourceId $ResourceId -OktaResourceType $ResourceType
                }
            }
            Write-Log "Bulk provisioning complete for $($UserIds.Count) users."
        }
        "BulkDeprovision" {
            if ($UserIds.Count -eq 0 -or -not $ResourceId) { throw "UserIds and ResourceId required." }
            foreach ($uid in $UserIds) {
                if ($PSCmdlet.ShouldProcess($uid, "Bulk deprovision from $ResourceType")) {
                    Revoke-Access -BaseUrl $baseUrl -Headers $headers -OktaUserId $uid `
                        -OktaResourceId $ResourceId -OktaResourceType $ResourceType
                }
            }
            Write-Log "Bulk deprovisioning complete for $($UserIds.Count) users."
        }
    }

    Write-Log "Action '$Action' completed successfully."
}
catch {
    Write-Log "Fatal error: $_" "ERROR"
    throw
}
