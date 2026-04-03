<#
.SYNOPSIS
    MFA policy enforcement and risk-based authentication management for Okta.

.DESCRIPTION
    Automates MFA policy creation, updates, and enrollment management.
    Supports risk-based authentication rules and adaptive MFA policies.

.PARAMETER Action
    The action to perform: CreatePolicy, UpdatePolicy, AssignPolicy, ListPolicies, EnforceCompliance.

.PARAMETER OktaDomain
    The Okta domain (e.g., company.okta.com).

.PARAMETER ApiToken
    The Okta API token for authentication.

.EXAMPLE
    .\mfa-policy-enforcement.ps1 -Action EnforceCompliance -OktaDomain "company.okta.com" -ApiToken $token

.NOTES
    Author:  Okta IGA Automation
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("CreatePolicy", "UpdatePolicy", "AssignPolicy", "ListPolicies", "EnforceCompliance")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$OktaDomain,

    [Parameter(Mandatory = $true)]
    [SecureString]$ApiToken,

    [Parameter(Mandatory = $false)]
    [string]$PolicyId,

    [Parameter(Mandatory = $false)]
    [string]$GroupId,

    [Parameter(Mandatory = $false)]
    [hashtable]$PolicyConfig = @{},

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs\mfa-policy.log"
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

function Invoke-OktaApi {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body = $null)
    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ContentType = "application/json" }
    if ($Body) { $params["Body"] = $Body }
    return Invoke-RestMethod @params
}

function Get-MfaPolicies {
    param([string]$BaseUrl, [hashtable]$Headers)
    Write-Log "Fetching MFA policies..."
    $uri = "$BaseUrl/api/v1/policies?type=MFA_ENROLL"
    return Invoke-OktaApi -Method GET -Uri $uri -Headers $Headers
}

function New-MfaPolicy {
    param([string]$BaseUrl, [hashtable]$Headers, [hashtable]$Config)
    Write-Log "Creating MFA policy: $($Config.name)"

    $policy = @{
        type        = "MFA_ENROLL"
        name        = $Config.name ?? "Corporate MFA Policy"
        description = $Config.description ?? "Enforces MFA enrollment for all users"
        status      = "ACTIVE"
        settings    = @{
            authenticators = @(
                @{ key = "okta_password";    enroll = @{ self = "REQUIRED" } }
                @{ key = "okta_email";       enroll = @{ self = "OPTIONAL" } }
                @{ key = "google_otp";       enroll = @{ self = "OPTIONAL" } }
                @{ key = "okta_verify";      enroll = @{ self = "REQUIRED" } }
                @{ key = "security_question"; enroll = @{ self = "OPTIONAL" } }
            )
        }
    } | ConvertTo-Json -Depth 10

    $uri = "$BaseUrl/api/v1/policies"
    $created = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers -Body $policy
    Write-Log "MFA policy created. ID: $($created.id)"
    return $created
}

function Update-MfaPolicy {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaPolicyId, [hashtable]$Config)
    Write-Log "Updating MFA policy: $OktaPolicyId"

    $updates = @{
        name        = $Config.name
        description = $Config.description
        status      = $Config.status ?? "ACTIVE"
    } | ConvertTo-Json -Depth 5

    $uri     = "$BaseUrl/api/v1/policies/$OktaPolicyId"
    $updated = Invoke-OktaApi -Method PUT -Uri $uri -Headers $Headers -Body $updates
    Write-Log "MFA policy $OktaPolicyId updated."
    return $updated
}

function Add-PolicyGroupTarget {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$OktaPolicyId, [string]$OktaGroupId)
    Write-Log "Assigning policy $OktaPolicyId to group $OktaGroupId"

    $rule = @{
        type     = "SIGN_ON"
        name     = "MFA Rule - Group Assignment"
        priority = 1
        status   = "ACTIVE"
        conditions = @{
            people = @{
                groups = @{
                    include = @($OktaGroupId)
                }
            }
        }
        actions = @{
            signon = @{
                access                 = "ALLOW"
                requireFactor          = $true
                factorPromptMode       = "ALWAYS"
                rememberDeviceLifetime = @{ usePersistentCookie = $false; deviceLifetimeinMinutes = 480 }
            }
        }
    } | ConvertTo-Json -Depth 10

    $uri    = "$BaseUrl/api/v1/policies/$OktaPolicyId/rules"
    $result = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers -Body $rule
    Write-Log "Policy rule created. ID: $($result.id)"
    return $result
}

function Invoke-MfaComplianceCheck {
    param([string]$BaseUrl, [hashtable]$Headers)
    Write-Log "Running MFA compliance check..."

    # Fetch all users
    $usersUri  = "$BaseUrl/api/v1/users?limit=200&filter=status+eq+%22ACTIVE%22"
    $users     = Invoke-OktaApi -Method GET -Uri $usersUri -Headers $Headers
    $nonCompliant = @()

    foreach ($user in $users) {
        $factorsUri = "$BaseUrl/api/v1/users/$($user.id)/factors"
        try {
            $factors = Invoke-OktaApi -Method GET -Uri $factorsUri -Headers $Headers
            $activeFactor = $factors | Where-Object { $_.status -eq "ACTIVE" }
            if (-not $activeFactor) {
                $nonCompliant += $user
                Write-Log "Non-compliant (no active MFA): $($user.profile.login)" "WARN"
            }
        }
        catch {
            Write-Log "Could not check factors for $($user.profile.login): $_" "WARN"
        }
    }

    Write-Log "Compliance check complete. Non-compliant users: $($nonCompliant.Count)/$($users.Count)"
    return @{
        TotalUsers       = $users.Count
        CompliantUsers   = $users.Count - $nonCompliant.Count
        NonCompliantUsers = $nonCompliant
    }
}

# ─── Main ────────────────────────────────────────────────────────────────────

try {
    $baseUrl = "https://$OktaDomain"
    $headers = Get-OktaHeaders -Token $ApiToken

    Write-Log "Action: $Action"

    switch ($Action) {
        "ListPolicies"    { return Get-MfaPolicies  -BaseUrl $baseUrl -Headers $headers }
        "CreatePolicy"    { return New-MfaPolicy    -BaseUrl $baseUrl -Headers $headers -Config $PolicyConfig }
        "UpdatePolicy" {
            if (-not $PolicyId) { throw "PolicyId required for UpdatePolicy." }
            return Update-MfaPolicy -BaseUrl $baseUrl -Headers $headers -OktaPolicyId $PolicyId -Config $PolicyConfig
        }
        "AssignPolicy" {
            if (-not $PolicyId -or -not $GroupId) { throw "PolicyId and GroupId required for AssignPolicy." }
            return Add-PolicyGroupTarget -BaseUrl $baseUrl -Headers $headers -OktaPolicyId $PolicyId -OktaGroupId $GroupId
        }
        "EnforceCompliance" { return Invoke-MfaComplianceCheck -BaseUrl $baseUrl -Headers $headers }
    }
}
catch {
    Write-Log "Fatal error: $_" "ERROR"
    throw
}
