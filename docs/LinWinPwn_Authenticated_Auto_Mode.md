# LinWinPwn Authenticated Auto Mode

> Documentation of all functions executed during authenticated Auto mode, in order of execution.

---

## Overview

The **authenticated Auto mode** is triggered by the `--auto` flag with valid credentials:

```bash
./linWinPwn.sh -t <DC_IP> -d <DOMAIN> -u <USERNAME> -p <PASSWORD> --auto
```

**Authentication methods supported:**
- Password (`-p`)
- NTLM Hash (`-H`)
- Kerberos Ticket (`-K`)
- AES Key (`-A`)
- PFX Certificate (`-C`)

---

## Execution Flow Diagram

```
main()
├── print_banner()
├── prepare()
├── print_info()
└── [Auto Mode Sequence]
    ├── authenticate()
    ├── parse_users()
    ├── parse_servers()
    ├── dns_enum()
    ├── ad_enum()
    ├── adcs_enum()
    ├── sccm_enum()
    ├── gpo_enum()
    ├── bruteforce()
    ├── kerberos()
    ├── netscan_run()
    ├── scan_shares()
    ├── vuln_checks()
    └── mssql_checks()
```

---

## 1. prepare()

**Location:** `linWinPwn.sh:453`

**Purpose:** Initialize script environment and validate target accessibility.

**Operations:**
- Validates DC IP address format
- Tests connectivity via LDAP, SMB, or MSSQL
- Extracts DC NETBIOS name and domain automatically
- Detects LDAP signing and channel binding enforcement
- Creates output directory structure
- Scans target for main ports (135, 445, 389, 636, 88, 3389, 5985)
- Runs optional auto-config (NTP sync, hosts file, DNS config, Kerberos config)

**Output Directory:**
```
linWinPwn_<domain>/
├── Users/
├── Servers/
├── Credentials/
├── DomainRecon/
├── ADCS/
├── SCCM/
├── Config/
├── Scans/
├── BruteForce/
├── Vulnerabilities/
├── Kerberos/
├── Shares/
├── GPO/
├── Modification/
├── CommandExec/
└── MSSQL/
```

---

## 2. authenticate()

**Location:** `linWinPwn.sh:659`

**Purpose:** Setup authentication arguments based on provided credentials.

**Operations:**
- Determines authentication method (password, hash, Kerberos, AES, certificate)
- Builds tool-specific argument strings for each authentication method
- Converts PFX certificates to PEM format if needed
- Detects and handles LDAP signing/binding requirements
- Extracts NTLM hash from certificates using PKINIT if needed

---

## 3. parse_users()

**Location:** `linWinPwn.sh:1042`

**Purpose:** Consolidate user lists from enumeration results.

**Operations:**
- Merges user lists from all enumeration tools into single file
- Ensures authenticated user is included in the list

**Output:** `users_list_${dc_domain}.txt`

---

## 4. parse_servers()

**Location:** `linWinPwn.sh:1030`

**Purpose:** Consolidate server/computer lists from enumeration results.

**Operations:**
- Merges server lists from all enumeration tools
- Separates Domain Controllers from regular servers
- Ensures DC IP is included in both lists

**Output:**
- `servers_list_${dc_domain}.txt`
- `servers_ip_list_${dc_domain}.txt`

---

## 5. dns_enum()

**Location:** `linWinPwn.sh:1048`

**Purpose:** Enumerate DNS records using netexec.

**Operations:**
- Uses `netexec ldap ... -M get-network` to dump DNS zone records
- Extracts IPs and hostnames from DNS records
- Parses server lists from DNS data
- Calls `parse_servers()` to integrate results

**Output:** `dns_records_${dc_domain}.txt`

---

## 6. ad_enum()

**Location:** `linWinPwn.sh:4749`

**Purpose:** Active Directory enumeration - the most comprehensive enumeration phase.

### 6.1 bhdce_enum()

**Location:** `linWinPwn.sh:1209`

**Tool:** `bloodhound-python`

**Purpose:** BloodHound Community Edition enumeration.

**Operations:**
- Collects all methods: users, computers, groups, OUs, relationships
- Uses collection methods: `all`, `LoggedOn`
- Extracts users and computers from JSON output

**Output:** `BloodHoundCE_${user_var}/` directory with JSON files

---

### 6.2 ldapdomaindump_enum()

**Location:** `linWinPwn.sh:1275`

**Tool:** `ldapdomaindump`

**Purpose:** Complete LDAP structure dump.

**Operations:**
- Dumps domain users, computers, groups, group policies
- Exports in JSON format

**Output:** `LDAPDomainDump/` directory with JSON files

---

### 6.3 enum4linux_enum()

**Location:** `linWinPwn.sh:1308`

**Tool:** `enum4linux-ng`

**Purpose:** Comprehensive SMB/RPC enumeration.

**Operations:**
- Enumerates shares, users, groups, and policies
- Parses user lists from output

**Output:** `enum4linux_${dc_domain}.json`

---

### 6.4 ne_ldap_usersenum()

**Location:** `linWinPwn.sh:1358`

**Tool:** `netexec ldap`

**Purpose:** User enumeration via LDAP.

**Output:** `ne_users_auth_ldap_${dc_domain}.txt`

---

### 6.5 ne_ldap_enum()

**Location:** `linWinPwn.sh:1375`

**Tool:** `netexec ldap` with various modules

**Purpose:** Extended LDAP enumeration.

**Operations:**
- DC list enumeration
- Password-not-required users detection
- Users with descriptions containing "pass"
- userPassword and unixUserPassword attributes

**Output:** Multiple files with DC and user information

---

### 6.6 ne_passpol()

**Location:** `linWinPwn.sh:1352`

**Tool:** `netexec smb`

**Purpose:** Password Policy enumeration.

**Output:** `ne_smbpasspol_output_${dc_domain}.txt`

---

### 6.7 deleg_enum()

**Location:** `linWinPwn.sh:1410`

**Tools:** `impacket-findDelegation`, `netexec ldap`

**Purpose:** Kerberos delegation enumeration.

**Operations:**
- Finds constrained delegation
- Finds unconstrained delegation
- Finds resource-based constrained delegation (RBCD)
- Uses netexec modules: `find-delegation`, `trusted-for-delegation`

**Output:**
- `impacket_findDelegation_output_${dc_domain}.txt`
- `ne_findDelegation_${dc_domain}.txt`

---

### 6.8 bloodyad_all_enum()

**Location:** `linWinPwn.sh:1433`

**Tool:** `bloodyAD`

**Purpose:** bloodyAD comprehensive enumeration.

**Operations:**
- Forest level (msDS-Behavior-Version)
- Machine Account Quota (ms-DS-MachineAccountQuota)
- Minimum password length (minPwdLength)
- All users, computers, containers
- Kerberoastable users
- ASREProastable users

**Output:** `bloodyAD/` directory

---

### 6.9 bloodyad_write_enum()

**Location:** `linWinPwn.sh:1473`

**Tool:** `bloodyAD`

**Purpose:** Find writable objects enumeration.

**Operations:**
- Searches for objects writable by the current user

**Output:** `bloodyad_writable_${user_out}_${dc_domain}.txt`

---

### 6.10 windapsearch_enum()

**Location:** `linWinPwn.sh:1604`

**Tool:** `windapsearch`

**Purpose:** LDAP enumeration via windapsearch.

**Operations:**
- Users (full details)
- Computers (full details)
- Groups (full details)
- Privileged users
- SPNs (Service Principal Names)
- Managed by relationships
- MSSQL servers
- Password fields in LDAP

**Output:** `windapsearch/` directory

---

## 7. adcs_enum()

**Location:** `linWinPwn.sh:4770`

**Purpose:** Active Directory Certificate Services (ADCS/PKI) enumeration.

### 7.1 ne_adcs_enum()

**Location:** `linWinPwn.sh:1945`

**Tool:** `netexec ldap -M adcs`

**Purpose:** Basic ADCS enumeration.

**Operations:**
- Enumerates PKI infrastructure
- Finds PKI Enrollment Servers and CAs

**Output:** `ne_adcs_output_${user_var}.txt`

---

### 7.2 certi_py_enum()

**Location:** `linWinPwn.sh:1958`

**Tool:** `certi.py`

**Purpose:** Certificate enumeration.

**Operations:**
- Lists CAs and certificate services
- Identifies certificate templates

**Output:** `certi.py_CA_output_${user_var}.txt`

---

### 7.3 certipy_enum()

**Location:** `linWinPwn.sh:1974`

**Tool:** `certipy`

**Purpose:** Advanced ADCS vulnerability scanning.

**Operations:**
- Scans for vulnerable ESC paths (ESC1-ESC10)
- Identifies exploitable certificate templates

**Output:** `vuln_${domain}_Certipy.json`

---

### 7.4 certifried_check()

**Location:** `linWinPwn.sh:2180`

**Tool:** `certipy`

**Purpose:** Certifried vulnerability check (ESC12).

---

## 8. sccm_enum()

**Location:** `linWinPwn.sh:4782`

**Purpose:** System Center Configuration Manager enumeration.

### 8.1 ne_sccm()

**Location:** `linWinPwn.sh:2312`

**Tool:** `netexec ldap -M sccm`

**Purpose:** Basic SCCM enumeration via netexec.

**Output:** `SCCM/` directory

---

### 8.2 sccmhunter_enum()

**Location:** `linWinPwn.sh:2318`

**Tool:** `sccmhunter`

**Purpose:** Advanced SCCM hunting.

**Output:** `SCCM/` directory

---

## 9. gpo_enum()

**Location:** `linWinPwn.sh:4791`

**Purpose:** Group Policy Object enumeration.

### 9.1 ne_gpp()

**Location:** `linWinPwn.sh:2407`

**Tool:** `netexec smb -M gpp_autologin`, `netexec smb -M gpp_password`

**Purpose:** Group Policy Preferences enumeration.

**Operations:**
- Extracts GPP autologin credentials
- Extracts GPP passwords

**Output:** `GPO/` directory

---

### 9.2 gpoparser_enum()

**Location:** `linWinPwn.sh:2429`

**Tool:** Custom GPO parsing

**Purpose:** GPO XML parsing.

**Operations:**
- Parses GPO XML files
- Extracts embedded credentials

**Output:** `GPO/` directory

---

## 10. bruteforce()

**Location:** `linWinPwn.sh:4801`

**Purpose:** Brute force and password spraying attacks.

### 10.1 userpass_kerbrute_check()

**Location:** `linWinPwn.sh:2518`

**Tool:** `kerbrute`

**Purpose:** Kerberos password spraying.

**Operations:**
- Performs password spraying against user list
- Uses supplied user and password lists

**Output:** `BruteForce/` directory

---

### 10.2 ne_pre2k()

**Tool:** `netexec ldap -M pre2k`

**Purpose:** Pre-Windows 2000 computer account enumeration.

**Operations:**
- Finds legacy computer accounts vulnerable to pre-authentication attacks

---

### 10.3 ne_timeroast()

**Location:** `linWinPwn.sh:2663`

**Tool:** `netexec ldap -M timeroast`

**Purpose:** Timeroast attack check.

---

## 11. kerberos()

**Location:** `linWinPwn.sh:4816`

**Purpose:** Kerberos-based attacks.

### 11.1 asrep_attack()

**Location:** `linWinPwn.sh:2685`

**Tool:** `impacket-GetNPUsers`

**Purpose:** AS-REP Roasting.

**Operations:**
- Targets users with pre-authentication disabled
- Extracts AS-REP hashes

**Output:** `asreproast_hashes_${dc_domain}.txt`

---

### 11.2 kerberoast_attack()

**Location:** `linWinPwn.sh:2762`

**Tool:** `impacket-GetUserSPNs`

**Purpose:** Kerberoasting.

**Operations:**
- Extracts TGS tickets for accounts with SPNs

**Output:** `kerberoast_hashes_${dc_domain}.txt`

---

### 11.3 john_crack_asrep()

**Location:** `linWinPwn.sh:2901`

**Tool:** `john`

**Purpose:** Crack AS-REP hashes.

**Operations:**
- Uses rockyou.txt wordlist by default

**Output:** `asreproast_john_results_${dc_domain}.txt`

---

### 11.4 john_crack_kerberoast()

**Location:** `linWinPwn.sh:2920`

**Tool:** `john`

**Purpose:** Crack Kerberoast hashes.

**Output:** `kerberoast_john_results_${dc_domain}.txt`

---

### 11.5 nopac_check()

**Location:** `linWinPwn.sh:2853`

**Tool:** `netexec smb -M nopac`

**Purpose:** NoPac vulnerability check (CVE-2021-42278, CVE-2021-42287).

---

### 11.6 ms14_068_check()

**Location:** `linWinPwn.sh:2870`

**Tool:** `netexec smb -M ms14-068`

**Purpose:** MS14-068 Kerberos vulnerability check.

---

## 12. netscan_run()

**Location:** `linWinPwn.sh:4874`

**Purpose:** Network port scanning.

### 12.1-12.4 ne_scan()

**Tool:** `netexec`

**Purpose:** Protocol-specific port scanning.

**Protocols scanned:**
1. SMB (port 445)
2. WinRM (port 5985)
3. SSH (port 22)
4. MSSQL (port 1433)

**Output:** `Scans/` directory

---

### 12.5 nhd_scan()

**Tool:** `nmap`

**Purpose:** Network Host Discovery.

**Output:** `Scans/` directory

---

## 13. scan_shares()

**Location:** `linWinPwn.sh:4834`

**Purpose:** Network share enumeration.

### 13.1 ne_shares()

**Location:** `linWinPwn.sh:2982`

**Tool:** `netexec smb --shares`

**Purpose:** Enumerate accessible shares.

**Output:** `ne_shares_output_${user_var}.txt`

---

### 13.2 ne_spider()

**Location:** `linWinPwn.sh:2994`

**Tool:** `netexec smb -M spider_plus`

**Purpose:** Spider shares for files.

**Operations:**
- Recursively lists files on accessible shares
- Excludes system shares (IPC$, SYSVOL, NETLOGON, etc.)

**Output:** `ne_spider_plus_${user_var}/` directory

---

### 13.3 finduncshar_scan()

**Location:** `linWinPwn.sh:3005`

**Tool:** `FindUncommonShares`

**Purpose:** Find uncommon/interesting shares.

**Operations:**
- Identifies non-standard shares
- Checks user access permissions
- Exports results to XLSX

**Output:** `finduncshar_${user_var}.xlsx`

---

## 14. vuln_checks()

**Location:** `linWinPwn.sh:4841`

**Purpose:** Vulnerability scanning.

### 14.1 print_check()

**Location:** `linWinPwn.sh:3228`

**Tool:** `netexec smb -M spooler`, `netexec smb -M printnightmare`

**Purpose:** Print Spooler vulnerability checks.

**Operations:**
- Checks for PrinterSpooler vulnerability
- Checks for PrintNightmare vulnerability

---

### 14.2 webdav_check()

**Location:** `linWinPwn.sh:3235`

**Tool:** `netexec smb -M webdav`

**Purpose:** WebDAV vulnerability check.

---

### 14.3 coerceplus_check()

**Location:** `linWinPwn.sh:3192`

**Tool:** `coercer`

**Purpose:** Coercion vulnerability checks.

**Operations:**
- Checks for credential coercion vulnerabilities (PetitPotam, etc.)

---

### 14.4 smb_checks()

**Location:** `linWinPwn.sh:3250`

**Tool:** `netexec smb` with various modules

**Purpose:** SMB security checks.

**Operations:**
- NTLMv1 usage check
- SMBGhost vulnerability check (CVE-2020-0796)
- Remove-MIC attack check

---

### 14.5 ldapnightmare_check()

**Location:** `linWinPwn.sh:3348`

**Tool:** Custom LDAP checks

**Purpose:** LDAP vulnerability checks.

---

### 14.6 badsuccessor_check()

**Location:** `linWinPwn.sh:3380`

**Tools:** `netexec ldap -M badsuccessor`, `impacket-badsuccessor`

**Purpose:** BadSuccessor vulnerability check.

**Operations:**
- Checks for certificate-based privilege escalation

---

## 15. mssql_checks()

**Location:** `linWinPwn.sh:4851`

**Purpose:** MSSQL server enumeration.

### 15.1 mssql_enum()

**Location:** `linWinPwn.sh:3399`

**Tool:** `netexec mssql`

**Purpose:** MSSQL server enumeration.

**Operations:**
- Consolidates MSSQL server lists from all sources
- Extracts IPs from DNS records

**Output:** `MSSQL/` directory

---

### 15.2 mssql_relay_check()

**Location:** `linWinPwn.sh:3425`

**Tool:** `netexec mssql`

**Purpose:** MSSQL relay vulnerability check.

---

## Summary Table

| Order | Function | Sub-Functions | Purpose |
|-------|----------|---------------|---------|
| 1 | `prepare()` | - | Initialize environment |
| 2 | `authenticate()` | - | Setup credentials |
| 3 | `parse_users()` | - | Consolidate users |
| 4 | `parse_servers()` | - | Consolidate servers |
| 5 | `dns_enum()` | - | DNS enumeration |
| 6 | `ad_enum()` | 10 | AD enumeration |
| 7 | `adcs_enum()` | 4 | PKI enumeration |
| 8 | `sccm_enum()` | 2 | SCCM enumeration |
| 9 | `gpo_enum()` | 2 | GPO enumeration |
| 10 | `bruteforce()` | 3 | Password attacks |
| 11 | `kerberos()` | 6 | Kerberos attacks |
| 12 | `netscan_run()` | 5 | Network scans |
| 13 | `scan_shares()` | 3 | Share enumeration |
| 14 | `vuln_checks()` | 6 | Vulnerability scans |
| 15 | `mssql_checks()` | 2 | MSSQL enumeration |

---

## Tags

#linWinPwn #ActiveDirectory #Pentesting #Security #Enumeration
