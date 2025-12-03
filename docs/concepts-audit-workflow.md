---
# Ansible Lockdown Audit & Reporting Concept
# This document explains how to generate and use compliance reports
---

# CIS Compliance Audit Workflow

## Overview

The Ansible Lockdown roles include built-in audit capabilities that generate 
compliance reports without making changes to systems. This is useful for:

- **Continuous compliance monitoring**
- **Pre/post hardening validation**
- **Audit evidence for security teams**
- **Dashboard/reporting integration**

---

## Audit Flow Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                         AUDIT WORKFLOW                                  │
└────────────────────────────────────────────────────────────────────────┘

  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────┐
  │   Ansible   │────►│   Target    │────►│   Fetch     │────►│ Process  │
  │  Playbook   │     │   Audit     │     │   Reports   │     │ & Store  │
  │ (audit mode)│     │ (goss/PS)   │     │  (JSON)     │     │          │
  └─────────────┘     └─────────────┘     └─────────────┘     └──────────┘
                                                                    │
                      ┌─────────────────────────────────────────────┤
                      │                                             │
                      ▼                                             ▼
               ┌─────────────┐                              ┌─────────────┐
               │  Dashboard  │                              │  Dynatrace  │
               │  (HTML/React)│                              │  Metrics    │
               └─────────────┘                              └─────────────┘
```

---

## Configuration

### Linux (Ubuntu 22.04 CIS)

Add to `group_vars/linux.yml`:

```yaml
# =====================================================
# AUDIT CONFIGURATION
# =====================================================

# Enable audit mode - runs goss tests
run_audit: true

# Run audit BEFORE applying changes (baseline)
audit_before: true

# Run audit AFTER applying changes (validation)
audit_after: true

# Output directory on target host
audit_output_dir: /opt/cis_audit

# Output format: json, documentation, or junit
audit_output_format: json

# Fetch reports back to Ansible controller
fetch_audit_output: true
fetch_audit_output_dir: ./audit_reports/

# Goss binary location (auto-downloaded if not present)
goss_version: "0.3.21"
```

### Windows (Server 2022 CIS)

Add to `group_vars/windows.yml`:

```yaml
# =====================================================
# AUDIT CONFIGURATION  
# =====================================================

# Enable audit mode
win2022cis_run_audit: true

# Output directory on target
win2022cis_audit_output_dir: C:\CIS_Audit

# Output format
win2022cis_audit_output_format: json

# Fetch reports
win2022cis_fetch_audit_output: true
win2022cis_fetch_audit_output_dir: ./audit_reports/
```

---

## Running Audits

### Audit Only (No Changes)

```powershell
# Check mode + audit - reports compliance without changing anything
.\ansible.cmd playbook cis-hardening-all.yml --check --tags audit
```

### Full Run with Audit

```powershell
# Apply hardening + generate audit report
.\ansible.cmd playbook cis-hardening-all.yml
```

### Scheduled Audit (Compliance Check)

Create `cis-audit-only.yml`:

```yaml
---
- name: CIS Compliance Audit - Linux
  hosts: linux
  become: yes
  vars:
    run_audit: true
    audit_only: true  # Skip remediation, audit only
  roles:
    - role: ubuntu22_cis

- name: CIS Compliance Audit - Windows
  hosts: windows
  vars:
    win2022cis_run_audit: true
    win2022cis_audit_only: true
  roles:
    - role: win2022_cis
```

Run weekly/daily via cron or scheduled task.

---

## Report Structure

### Linux (Goss) JSON Output

```json
{
  "results": [
    {
      "resource-type": "Command",
      "resource-id": "CIS 3.3.1 - Ensure source routed packets are not accepted",
      "property": "exit-status",
      "result": "success",
      "expected": ["0"],
      "found": ["0"],
      "duration": 45623
    },
    {
      "resource-type": "Command",
      "resource-id": "CIS 3.3.8 - Ensure TCP SYN Cookies is enabled",
      "property": "exit-status", 
      "result": "failure",
      "expected": ["0"],
      "found": ["1"],
      "duration": 38291
    }
  ],
  "summary": {
    "test-count": 150,
    "failed-count": 3,
    "skipped-count": 12,
    "duration": 15234567
  }
}
```

### Windows (Audit Script) JSON Output

```json
{
  "hostname": "vm-win-demo",
  "timestamp": "2024-01-15T10:30:00Z",
  "profile": "Windows-2022-CIS-L1",
  "results": [
    {
      "id": "1.1.2",
      "title": "Ensure 'Maximum password age' is set to '365 or fewer days'",
      "status": "PASS",
      "expected": "<=365",
      "actual": "90"
    },
    {
      "id": "17.1.1",
      "title": "Ensure 'Audit Credential Validation' is set to 'Success and Failure'",
      "status": "FAIL",
      "expected": "Success and Failure",
      "actual": "No Auditing"
    }
  ],
  "summary": {
    "total": 45,
    "passed": 42,
    "failed": 2,
    "skipped": 1,
    "compliance_percentage": 93.3
  }
}
```

---

## Report Directory Structure

After running audits:

```
audit_reports/
├── linux/
│   └── vm-linux-demo/
│       ├── audit_2024-01-15_103000.json
│       ├── audit_2024-01-14_103000.json
│       └── latest.json -> audit_2024-01-15_103000.json
├── windows/
│   └── vm-win-demo/
│       ├── audit_2024-01-15_103000.json
│       └── latest.json -> audit_2024-01-15_103000.json
└── summary/
    └── compliance_summary.json
```

---

## Integration Options

### 1. Local Dashboard (HTML/React)

View `docs/cis-dashboard.html` for a local dashboard that reads JSON reports.

### 2. Dynatrace Metrics

Parse JSON and push to Dynatrace Metrics API:

```python
import json
import requests

def push_to_dynatrace(report_path, dt_url, dt_token):
    with open(report_path) as f:
        report = json.load(f)
    
    summary = report['summary']
    hostname = report.get('hostname', 'unknown')
    
    metrics = f"""
cis.compliance.score,host={hostname} {summary['compliance_percentage']}
cis.controls.passed,host={hostname} {summary['passed']}
cis.controls.failed,host={hostname} {summary['failed']}
cis.controls.total,host={hostname} {summary['total']}
"""
    
    requests.post(
        f"{dt_url}/api/v2/metrics/ingest",
        headers={"Authorization": f"Api-Token {dt_token}"},
        data=metrics
    )
```

### 3. CI/CD Pipeline

```yaml
# Azure DevOps / GitHub Actions
- name: Run CIS Audit
  run: .\ansible.cmd playbook cis-audit-only.yml

- name: Check Compliance Threshold
  run: |
    $report = Get-Content audit_reports/summary/compliance_summary.json | ConvertFrom-Json
    if ($report.overall_compliance -lt 90) {
      Write-Error "Compliance below 90% threshold"
      exit 1
    }
```

---

## Next Steps

1. Enable audit in group_vars
2. Run audit playbook
3. Review JSON reports
4. Set up dashboard or Dynatrace integration
5. Schedule regular compliance checks
