<#
.SYNOPSIS
    Automated user lifecycle management for Okta IGA.

.DESCRIPTION
    Handles user provisioning, updates, and deactivation in Okta via the Okta Management API.
    Supports Joiner-Mover-Leaver (JML) workflows for enterprise identity governance.

.PARAMETER Action
    The lifecycle action to perform: Create, Update, or Deactivate.

.PARAMETER OktaDomain
    The Okta domain (e.g., company.okta.com).

.PARAMETER ApiToken
    The Okta API token for authentication.

.PARAMETER UserData
    A hashtable containing user attributes.

.EXAMPLE
    .\user-provisioning.ps1 -Action Create -OktaDomain "company.okta.com" -ApiToken $token -UserData @{login="jdoe@company.com"; firstName="John"; lastName="Doe"}

.NOTES
    Author:      Okta IGA Automation
    Version:     1.0.0
    Requires:    PowerShell 7+
    License:     MIT
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Create", "Update", "Deactivate", "Reactivate", "Suspend", "Unsuspend")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$OktaDomain,

    [Parameter(Mandatory = $true)]
    [SecureString]$ApiToken,

    [Parameter(Mandatory = $false)]
    [hashtable]$UserData = @{},

    [Parameter(Mandatory = $false)]
    [string]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs\user-provisioning.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    if (-not (Test-Path (Split-Path $LogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
    }
    Add-Content -Path $LogPath -Value $logEntry
}

function Get-OktaHeaders {
    param([SecureString]$Token)
    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    )
    return @{
        "Authorization" = "SSWS $plainToken"
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
    }
}

function Invoke-OktaApi {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body = $null,
        [int]$MaxRetries = 3
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Method      = $Method
                Uri         = $Uri
                Headers     = $Headers
                ContentType = "application/json"
            }
            if ($Body) { $params["Body"] = $Body }
            $response = Invoke-RestMethod @params
            return $response
        }
        catch {
            $attempt++
            $statusCode = $_.Exception.Response?.StatusCode?.value__
            if ($statusCode -eq 429) {
                # Rate-limited – honour the Retry-After header
                $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                $wait = if ($retryAfter) { [int]$retryAfter } else { [math]::Pow(2, $attempt) }
                Write-Log "Rate limited. Retrying after ${wait}s (attempt $attempt/$MaxRetries)." "WARN"
                Start-Sleep -Seconds $wait
            }
            elseif ($attempt -ge $MaxRetries) {
                Write-Log "API call failed after $MaxRetries attempts: $_" "ERROR"
                throw
            }
            else {
                $wait = [math]::Pow(2, $attempt)
                Write-Log "API error (attempt $attempt/$MaxRetries). Retrying in ${wait}s: $_" "WARN"
                Start-Sleep -Seconds $wait
            }
        }
    }
}

#endregion

#region User Lifecycle Functions

function New-OktaUser {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [hashtable]$UserAttributes
    )
    Write-Log "Creating user: $($UserAttributes.login)"

    $body = @{
        profile    = @{
            firstName   = $UserAttributes.firstName
            lastName    = $UserAttributes.lastName
            email       = $UserAttributes.email ?? $UserAttributes.login
            login       = $UserAttributes.login
            department  = $UserAttributes.department
            title       = $UserAttributes.title
            mobilePhone = $UserAttributes.mobilePhone
        }
        credentials = @{
            password = @{ value = $UserAttributes.tempPassword ?? [System.Web.Security.Membership]::GeneratePassword(16, 4) }
        }
    } | ConvertTo-Json -Depth 5

    $uri      = "$BaseUrl/api/v1/users?activate=true"
    $newUser  = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers -Body $body
    Write-Log "User created successfully. ID: $($newUser.id)" "INFO"
    return $newUser
}

function Update-OktaUser {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$OktaUserId,
        [hashtable]$UserAttributes
    )
    Write-Log "Updating user: $OktaUserId"

    $profileUpdates = @{}
    $allowedFields  = @("firstName", "lastName", "email", "department", "title", "mobilePhone", "manager")
    foreach ($field in $allowedFields) {
        if ($UserAttributes.ContainsKey($field)) {
            $profileUpdates[$field] = $UserAttributes[$field]
        }
    }

    $body    = @{ profile = $profileUpdates } | ConvertTo-Json -Depth 5
    $uri     = "$BaseUrl/api/v1/users/$OktaUserId"
    $updated = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers -Body $body
    Write-Log "User $OktaUserId updated successfully." "INFO"
    return $updated
}

function Disable-OktaUser {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$OktaUserId,
        [bool]$SendEmail = $false
    )
    Write-Log "Deactivating user: $OktaUserId"
    $uri = "$BaseUrl/api/v1/users/$OktaUserId/lifecycle/deactivate?sendEmail=$($SendEmail.ToString().ToLower())"
    Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId deactivated." "INFO"
}

function Enable-OktaUser {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$OktaUserId
    )
    Write-Log "Reactivating user: $OktaUserId"
    $uri = "$BaseUrl/api/v1/users/$OktaUserId/lifecycle/reactivate?sendEmail=true"
    $result = Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers
    Write-Log "User $OktaUserId reactivated." "INFO"
    return $result
}

function Suspend-OktaUserAccount {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$OktaUserId
    )
    Write-Log "Suspending user: $OktaUserId"
    $uri = "$BaseUrl/api/v1/users/$OktaUserId/lifecycle/suspend"
    Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId suspended." "INFO"
}

function Resume-OktaUserAccount {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$OktaUserId
    )
    Write-Log "Unsuspending user: $OktaUserId"
    $uri = "$BaseUrl/api/v1/users/$OktaUserId/lifecycle/unsuspend"
    Invoke-OktaApi -Method POST -Uri $uri -Headers $Headers | Out-Null
    Write-Log "User $OktaUserId unsuspended." "INFO"
}

function Get-OktaUser {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [string]$LoginOrId
    )
    $uri = "$BaseUrl/api/v1/users/$LoginOrId"
    return Invoke-OktaApi -Method GET -Uri $uri -Headers $Headers
}

#endregion

#region Main Execution

try {
    $baseUrl = "https://$OktaDomain"
    $headers = Get-OktaHeaders -Token $ApiToken

    Write-Log "Starting user lifecycle action: $Action"

    switch ($Action) {
        "Create" {
            if (-not $UserData.ContainsKey("login")) {
                throw "UserData must include a 'login' field for Create action."
            }
            if ($PSCmdlet.ShouldProcess($UserData.login, "Create Okta User")) {
                $result = New-OktaUser -BaseUrl $baseUrl -Headers $headers -UserAttributes $UserData
                Write-Log "Provisioning complete. Okta User ID: $($result.id)"
                return $result
            }
        }
        "Update" {
            if (-not $UserId) { throw "UserId is required for Update action." }
            if ($PSCmdlet.ShouldProcess($UserId, "Update Okta User")) {
                $result = Update-OktaUser -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId -UserAttributes $UserData
                return $result
            }
        }
        "Deactivate" {
            if (-not $UserId) { throw "UserId is required for Deactivate action." }
            if ($PSCmdlet.ShouldProcess($UserId, "Deactivate Okta User")) {
                Disable-OktaUser -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId
            }
        }
        "Reactivate" {
            if (-not $UserId) { throw "UserId is required for Reactivate action." }
            if ($PSCmdlet.ShouldProcess($UserId, "Reactivate Okta User")) {
                $result = Enable-OktaUser -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId
                return $result
            }
        }
        "Suspend" {
            if (-not $UserId) { throw "UserId is required for Suspend action." }
            if ($PSCmdlet.ShouldProcess($UserId, "Suspend Okta User")) {
                Suspend-OktaUserAccount -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId
            }
        }
        "Unsuspend" {
            if (-not $UserId) { throw "UserId is required for Unsuspend action." }
            if ($PSCmdlet.ShouldProcess($UserId, "Unsuspend Okta User")) {
                Resume-OktaUserAccount -BaseUrl $baseUrl -Headers $headers -OktaUserId $UserId
            }
        }
    }

    Write-Log "Action '$Action' completed successfully."
}
catch {
    Write-Log "Fatal error during '$Action': $_" "ERROR"
    throw
}

#endregion
