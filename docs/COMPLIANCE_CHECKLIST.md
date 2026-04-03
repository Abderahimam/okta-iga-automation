# Compliance Checklist

Regulatory compliance requirements for the Okta IGA Automation toolkit covering SOX, GDPR, and NIST frameworks.

---

## Table of Contents

1. [SOX (Sarbanes-Oxley) Compliance](#sox-sarbanes-oxley-compliance)
2. [GDPR Compliance](#gdpr-compliance)
3. [NIST Cybersecurity Framework](#nist-cybersecurity-framework)
4. [ISO 27001 Alignment](#iso-27001-alignment)
5. [Audit Evidence Collection](#audit-evidence-collection)

---

## SOX (Sarbanes-Oxley) Compliance

### Section 302 & 404 – Internal Controls

SOX requires organisations to maintain and assess the effectiveness of internal controls over financial reporting (ICFR). IAM automation directly supports these controls.

#### Access Control Requirements

- [ ] **Segregation of Duties (SoD)**: Users with access to financial systems cannot also administer those systems
- [ ] **Least Privilege**: User access limited to what is required for their role
- [ ] **Access Certification**: Quarterly review of all privileged and sensitive access
- [ ] **Provisioning Approval**: All access requests require documented business justification and manager approval
- [ ] **De-provisioning Timeliness**: Terminated employees de-provisioned within 24 hours
- [ ] **Privileged Access Management**: Privileged access requires additional authentication (MFA)

#### Change Management Controls

- [ ] All policy changes documented and approved prior to implementation
- [ ] Change log maintained with before/after states
- [ ] Emergency changes reviewed within 5 business days
- [ ] Production changes follow four-eyes principle

#### Evidence Requirements

| Control | Evidence Type | Frequency |
|---------|--------------|-----------|
| Access provisioning | Approved access request tickets | Per event |
| Access termination | Leaver processing report | Per event |
| Access certification | Signed certification report | Quarterly |
| Privileged access review | PAM audit report | Monthly |
| Policy changes | Change management records | Per change |
| SoD violations | Compensating control evidence | Per violation |

#### Relevant Automation Scripts

```powershell
# Generate SOX access certification report
.\okta-audit-reporting.ps1 `
    -OktaDomain $domain -ApiToken $token `
    -EventTypes @("user.lifecycle.create","user.lifecycle.deactivate","user.account.privilege.escalate") `
    -StartDate (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0) `
    -OutputPath ".\sox-evidence\$(Get-Date -Format 'yyyy-Qx')"
```

---

## GDPR Compliance

### Key GDPR Articles Relevant to IAM

#### Article 5 – Data Minimisation

- [ ] User profiles contain only data necessary for job function
- [ ] Excess personal data removed or anonymised
- [ ] Retention periods defined and enforced for all identity data

#### Article 17 – Right to Erasure

- [ ] Process documented for fulfilling erasure requests within 30 days
- [ ] User accounts can be fully deprovisioned and data anonymised
- [ ] Third-party integrations notified of deletion via SCIM DELETE

```python
# GDPR erasure via SCIM
provisioner.delete_user(user_id)  # Hard delete
# OR
provisioner.deactivate_user(user_id)  # Soft delete (set active=false)
```

#### Article 30 – Records of Processing

- [ ] Audit logs retained for at least 2 years
- [ ] Log export available in structured format (CSV/JSON)
- [ ] Processing activities documented in Data Processing Register

#### Article 32 – Security of Processing

- [ ] MFA enforced for all accounts with access to personal data
- [ ] Data-at-rest and data-in-transit encryption implemented
- [ ] Access to EU-resident personal data geo-restricted where required

#### Article 33 – Breach Notification

- [ ] Security incident response process documented
- [ ] Breach notification within 72 hours capability confirmed
- [ ] Contact details for Data Protection Officer (DPO) documented

#### Data Subject Requests (DSR) Workflow

```
1. DSR received via privacy portal
2. Identity verified (2-factor)
3. Search Okta System Log for all events related to data subject
4. Export user profile and activity
5. Fulfil request (access / rectification / erasure / portability)
6. Document fulfilment within 30 days
7. Log in DSR register
```

---

## NIST Cybersecurity Framework

### Framework Core Functions

#### IDENTIFY (ID)

- [ ] **ID.AM-1**: Physical devices and systems inventoried
- [ ] **ID.AM-2**: Software platforms and applications inventoried
- [ ] **ID.AM-3**: Organisational communication and data flows mapped
- [ ] **ID.AM-5**: Resources prioritised based on classification, criticality, and business value
- [ ] **ID.GV-1**: Organisational information security policy established
- [ ] **ID.RA-1**: Asset vulnerabilities identified and documented

#### PROTECT (PR)

- [ ] **PR.AC-1**: Identities and credentials managed for devices, users, and processes
- [ ] **PR.AC-2**: Physical access managed and protected
- [ ] **PR.AC-3**: Remote access managed
- [ ] **PR.AC-4**: Access permissions managed incorporating least privilege and SoD
- [ ] **PR.AC-5**: Network integrity protected (network segregation)
- [ ] **PR.AC-6**: Identities proofed, bound to credentials, and asserted in interactions
- [ ] **PR.AC-7**: Users, devices, and other assets authenticated commensurate with risk
- [ ] **PR.AT-1**: All users informed and trained on security responsibilities
- [ ] **PR.DS-1**: Data-at-rest protected
- [ ] **PR.DS-2**: Data-in-transit protected
- [ ] **PR.MA-1**: Maintenance and repair assets performed consistently with policies

#### DETECT (DE)

- [ ] **DE.AE-1**: Baseline of network operations and expected data flows established
- [ ] **DE.AE-3**: Event data aggregated and correlated from multiple sources
- [ ] **DE.CM-1**: Network monitored to detect potential cybersecurity events
- [ ] **DE.CM-3**: Personnel activity monitored to detect potential cybersecurity events
- [ ] **DE.CM-7**: Monitoring for unauthorised personnel, connections, devices, and software performed
- [ ] **DE.DP-4**: Event detection information communicated to appropriate parties

#### RESPOND (RS)

- [ ] **RS.RP-1**: Response plan executed during or after an incident
- [ ] **RS.CO-2**: Incidents reported consistent with established criteria
- [ ] **RS.AN-1**: Notifications from detection systems investigated
- [ ] **RS.MI-1**: Incidents contained
- [ ] **RS.MI-2**: Incidents mitigated
- [ ] **RS.IM-1**: Response plans incorporate lessons learned

#### RECOVER (RC)

- [ ] **RC.RP-1**: Recovery plan executed during or after a cybersecurity incident
- [ ] **RC.CO-3**: Recovery activities communicated to appropriate parties

---

## ISO 27001 Alignment

### Annex A Controls for IAM

| Control | Reference | Status |
|---------|-----------|--------|
| Information classification | A.8.2 | ☐ |
| Access control policy | A.9.1.1 | ☐ |
| User registration/de-registration | A.9.2.1 | ☐ |
| User access provisioning | A.9.2.2 | ☐ |
| Management of privileged access rights | A.9.2.3 | ☐ |
| Management of secret authentication information | A.9.2.4 | ☐ |
| Review of user access rights | A.9.2.5 | ☐ |
| Removal/adjustment of access rights | A.9.2.6 | ☐ |
| Use of secret authentication information | A.9.3.1 | ☐ |
| Information access restriction | A.9.4.1 | ☐ |
| Secure log-on procedures | A.9.4.2 | ☐ |
| Password management system | A.9.4.3 | ☐ |
| Audit logging | A.12.4.1 | ☐ |
| Protection of log information | A.12.4.2 | ☐ |
| Clock synchronisation | A.12.4.4 | ☐ |

---

## Audit Evidence Collection

### Automated Evidence Collection

Use the audit reporting script to collect evidence on a schedule:

```powershell
# Monthly SOX evidence package
$quarter = "Q$(([math]::Ceiling((Get-Date).Month/3)))-$(Get-Date -Format yyyy)"
$outDir  = ".\sox-evidence\$quarter"

.\powershell-scripts\okta-audit-reporting.ps1 `
    -OktaDomain $env:OKTA_DOMAIN `
    -ApiToken (ConvertTo-SecureString $env:OKTA_API_TOKEN -AsPlainText -Force) `
    -StartDate (Get-Date -Day 1 -Hour 0 -Minute 0) `
    -OutputPath $outDir `
    -OutputFormat CSV
```

### Evidence Retention Matrix

| Regulation | Minimum Retention | Recommended Retention |
|------------|-------------------|----------------------|
| SOX | 7 years | 10 years |
| GDPR | Duration of processing + 1 year | 2 years (audit logs) |
| NIST | Per organisational policy | 3 years |
| ISO 27001 | 3 years | 5 years |

### Evidence Integrity

- Export evidence in tamper-evident format (hash the files)
- Store evidence in immutable storage (S3 Object Lock / Azure Immutable Blob)
- Maintain chain of custody documentation

```bash
# Generate SHA-256 hash manifest for evidence package
find ./sox-evidence -type f -exec sha256sum {} \; > ./sox-evidence/manifest.sha256
gpg --armor --sign ./sox-evidence/manifest.sha256
```
