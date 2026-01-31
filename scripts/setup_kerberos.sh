#!/bin/bash
#
# setup_kerberos.sh - Configure Linux for Kerberos authentication against Active Directory
#
# Extracted and enhanced from linWinPwn by lefayjey
# https://github.com/lefayjey/linWinPwn
#
# This script configures:
#   - NTP time sync (Kerberos requires time within 5 minutes of DC)
#   - /etc/hosts entries for DC resolution
#   - /etc/resolv.conf for DNS resolution
#   - /etc/krb5.conf for Kerberos realm configuration
#
# Usage: ./setup_kerberos.sh -d <DOMAIN> -t <DC_IP> [options]
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
BACKUP_DIR="./kerberos_backups"
DNS_IP=""
DC_NETBIOS=""
QUIET=false
RESTORE=false
DRY_RUN=false

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║        Kerberos Setup Script for Active Directory         ║"
    echo "║              Extracted from linWinPwn                     ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    echo -e "${YELLOW}Usage:${NC} $0 -d <DOMAIN> -t <DC_IP> [options]"
    echo ""
    echo -e "${YELLOW}Required:${NC}"
    echo "  -d, --domain        Domain name (e.g., corp.local)"
    echo "  -t, --dc-ip         Domain Controller IP address"
    echo ""
    echo -e "${YELLOW}Optional:${NC}"
    echo "  -n, --dc-name       DC NetBIOS name (auto-detected if not specified)"
    echo "  -s, --dns-ip        DNS server IP (defaults to DC IP)"
    echo "  -b, --backup-dir    Backup directory (default: ./kerberos_backups)"
    echo "  -q, --quiet         Suppress non-essential output"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --restore           Restore from latest backups"
    echo "  --ntp-only          Only sync NTP time"
    echo "  --hosts-only        Only update /etc/hosts"
    echo "  --dns-only          Only update /etc/resolv.conf"
    echo "  --krb5-only         Only update /etc/krb5.conf"
    echo "  --skip-ntp          Skip NTP sync"
    echo "  --skip-hosts        Skip /etc/hosts update"
    echo "  --skip-dns          Skip /etc/resolv.conf update"
    echo "  --skip-krb5         Skip /etc/krb5.conf update"
    echo "  -h, --help          Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  # Full setup"
    echo "  $0 -d corp.local -t 10.10.10.10"
    echo ""
    echo "  # Setup with custom DC name"
    echo "  $0 -d corp.local -t 10.10.10.10 -n DC01"
    echo ""
    echo "  # Dry run to see what would change"
    echo "  $0 -d corp.local -t 10.10.10.10 --dry-run"
    echo ""
    echo "  # Only update krb5.conf"
    echo "  $0 -d corp.local -t 10.10.10.10 --krb5-only"
    echo ""
    echo "  # Restore from backups"
    echo "  $0 --restore"
    echo ""
    exit 0
}

log_info() {
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}[*]${NC} $1"
    fi
}

log_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[-]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}

check_dependencies() {
    local missing=()

    # Check for required commands
    for cmd in ntpdate dig host; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log_warning "Missing dependencies: ${missing[*]}"
        log_info "Install with: apt install ntpdate dnsutils"
    fi

    # Check for krb5-user
    if ! command -v kinit &> /dev/null; then
        log_warning "kinit not found. Install krb5-user for Kerberos ticket operations."
        log_info "Install with: apt install krb5-user"
    fi
}

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi
}

detect_dc_info() {
    if [ -z "$DC_NETBIOS" ]; then
        log_info "Attempting to detect DC NetBIOS name..."

        # Try nmblookup first
        if command -v nmblookup &> /dev/null; then
            DC_NETBIOS=$(nmblookup -A "$DC_IP" 2>/dev/null | grep '<00>' | head -1 | awk '{print $1}')
        fi

        # Try nmap if nmblookup failed
        if [ -z "$DC_NETBIOS" ] && command -v nmap &> /dev/null; then
            DC_NETBIOS=$(nmap -sU -p137 --script nbstat "$DC_IP" 2>/dev/null | grep "NetBIOS name:" | cut -d':' -f2 | tr -d ' ')
        fi

        # Fallback to domain prefix
        if [ -z "$DC_NETBIOS" ]; then
            DC_NETBIOS=$(echo "$DOMAIN" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
            log_warning "Could not detect DC NetBIOS name, using: $DC_NETBIOS"
        else
            log_success "Detected DC NetBIOS name: $DC_NETBIOS"
        fi
    fi

    # Set DNS IP to DC IP if not specified
    if [ -z "$DNS_IP" ]; then
        DNS_IP="$DC_IP"
    fi

    # Calculate FQDN
    DC_FQDN="${DC_NETBIOS,,}.${DOMAIN,,}"
}

# ========================
# NTP Time Sync
# ========================
sync_ntp() {
    log_info "Syncing time with Domain Controller..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY-RUN]${NC} Would run: timedatectl set-ntp 0"
        echo -e "${CYAN}[DRY-RUN]${NC} Would run: ntpdate $DC_IP"
        return
    fi

    # Disable automatic NTP
    timedatectl set-ntp 0 2>/dev/null

    # Sync with DC
    if command -v ntpdate &> /dev/null; then
        ntpdate "$DC_IP" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_success "NTP time sync complete"
        else
            log_warning "NTP sync failed. Trying alternative method..."
            # Try with net time if ntpdate fails
            if command -v net &> /dev/null; then
                net time set -S "$DC_IP" 2>/dev/null
            fi
        fi
    else
        log_warning "ntpdate not installed. Skipping NTP sync."
        log_info "Install with: apt install ntpdate"
    fi

    # Show current time offset (informational)
    log_info "Current system time: $(date)"
}

# ========================
# /etc/hosts Update
# ========================
update_hosts() {
    log_info "Updating /etc/hosts..."

    local HOSTS_FILE="/etc/hosts"
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local BACKUP_FILE="${BACKUP_DIR}/hosts.${TIMESTAMP}.backup"

    # Check if entry already exists
    if grep -q "$DC_IP" "$HOSTS_FILE" 2>/dev/null; then
        log_warning "DC IP already present in /etc/hosts"
        grep "$DC_IP" "$HOSTS_FILE"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY-RUN]${NC} Would backup $HOSTS_FILE to $BACKUP_FILE"
        echo -e "${CYAN}[DRY-RUN]${NC} Would add: $DC_IP    $DOMAIN $DC_FQDN $DC_NETBIOS"
        return
    fi

    # Create backup
    cp "$HOSTS_FILE" "$BACKUP_FILE"
    log_info "Backup created: $BACKUP_FILE"

    # Remove any existing entries for this DC (by FQDN)
    sed -i "/${DC_FQDN}/d" "$HOSTS_FILE"

    # Add new entry
    echo "# Added by setup_kerberos.sh for AD authentication" >> "$HOSTS_FILE"
    echo "$DC_IP    $DOMAIN $DC_FQDN $DC_NETBIOS" >> "$HOSTS_FILE"

    log_success "Hosts file updated"
    log_info "Added: $DC_IP    $DOMAIN $DC_FQDN $DC_NETBIOS"
}

# ========================
# /etc/resolv.conf Update
# ========================
update_resolv() {
    log_info "Updating /etc/resolv.conf..."

    local RESOLV_FILE="/etc/resolv.conf"
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local BACKUP_FILE="${BACKUP_DIR}/resolv.conf.${TIMESTAMP}.backup"

    # Check if entry already exists
    if grep -q "nameserver $DNS_IP" "$RESOLV_FILE" 2>/dev/null; then
        log_warning "DNS server already present in /etc/resolv.conf"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY-RUN]${NC} Would backup $RESOLV_FILE to $BACKUP_FILE"
        echo -e "${CYAN}[DRY-RUN]${NC} Would prepend: nameserver $DNS_IP"
        return
    fi

    # Create backup
    cp "$RESOLV_FILE" "$BACKUP_FILE"
    log_info "Backup created: $BACKUP_FILE"

    # Prepend DNS server (make it primary)
    local TEMP_FILE=$(mktemp)
    echo "# Added by setup_kerberos.sh for AD authentication" > "$TEMP_FILE"
    echo "nameserver $DNS_IP" >> "$TEMP_FILE"
    cat "$RESOLV_FILE" >> "$TEMP_FILE"
    mv "$TEMP_FILE" "$RESOLV_FILE"

    log_success "DNS resolver updated"
    log_info "Added nameserver: $DNS_IP"
}

# ========================
# /etc/krb5.conf Update
# ========================
update_krb5() {
    log_info "Updating /etc/krb5.conf..."

    local KRB5_FILE="/etc/krb5.conf"
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local BACKUP_FILE="${BACKUP_DIR}/krb5.conf.${TIMESTAMP}.backup"
    local REALM="${DOMAIN^^}"  # Uppercase domain

    # Check if domain already configured
    if grep -q "${DOMAIN,,}" "$KRB5_FILE" 2>/dev/null; then
        log_warning "Domain already present in /etc/krb5.conf"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}[DRY-RUN]${NC} Would backup $KRB5_FILE to $BACKUP_FILE"
        echo -e "${CYAN}[DRY-RUN]${NC} Would create new krb5.conf for realm: $REALM"
        echo -e "${CYAN}[DRY-RUN]${NC} KDC: $DC_FQDN"
        return
    fi

    # Create backup if file exists
    if [ -f "$KRB5_FILE" ]; then
        cp "$KRB5_FILE" "$BACKUP_FILE"
        log_info "Backup created: $BACKUP_FILE"
    fi

    # Write new krb5.conf
    cat > "$KRB5_FILE" << EOF
# /etc/krb5.conf - Generated by setup_kerberos.sh
# Domain: ${DOMAIN}
# DC: ${DC_FQDN}
# Generated: $(date)

[libdefaults]
        default_realm = ${REALM}
        kdc_timesync = 1
        ccache_type = 4
        forwardable = true
        proxiable = true
        rdns = false
        fcc-mit-ticketflags = true
        dns_canonicalize_hostname = false
        dns_lookup_realm = false
        dns_lookup_kdc = false
        k5login_authoritative = false

[realms]
        ${REALM} = {
                kdc = ${DC_FQDN}
                admin_server = ${DC_FQDN}
                default_domain = ${DOMAIN,,}
        }

[domain_realm]
        .${DOMAIN,,} = ${REALM}
        ${DOMAIN,,} = ${REALM}
EOF

    log_success "Kerberos configuration updated"
    log_info "Realm: $REALM"
    log_info "KDC: $DC_FQDN"
}

# ========================
# Restore from Backups
# ========================
restore_backups() {
    log_info "Restoring from backups in: $BACKUP_DIR"

    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi

    # Restore hosts
    local HOSTS_BACKUP=$(ls -t "${BACKUP_DIR}/hosts."*.backup 2>/dev/null | head -1)
    if [ -n "$HOSTS_BACKUP" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${CYAN}[DRY-RUN]${NC} Would restore /etc/hosts from $HOSTS_BACKUP"
        else
            cp "$HOSTS_BACKUP" /etc/hosts
            log_success "Restored /etc/hosts from $HOSTS_BACKUP"
        fi
    else
        log_warning "No hosts backup found"
    fi

    # Restore resolv.conf
    local RESOLV_BACKUP=$(ls -t "${BACKUP_DIR}/resolv.conf."*.backup 2>/dev/null | head -1)
    if [ -n "$RESOLV_BACKUP" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${CYAN}[DRY-RUN]${NC} Would restore /etc/resolv.conf from $RESOLV_BACKUP"
        else
            cp "$RESOLV_BACKUP" /etc/resolv.conf
            log_success "Restored /etc/resolv.conf from $RESOLV_BACKUP"
        fi
    else
        log_warning "No resolv.conf backup found"
    fi

    # Restore krb5.conf
    local KRB5_BACKUP=$(ls -t "${BACKUP_DIR}/krb5.conf."*.backup 2>/dev/null | head -1)
    if [ -n "$KRB5_BACKUP" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${CYAN}[DRY-RUN]${NC} Would restore /etc/krb5.conf from $KRB5_BACKUP"
        else
            cp "$KRB5_BACKUP" /etc/krb5.conf
            log_success "Restored /etc/krb5.conf from $KRB5_BACKUP"
        fi
    else
        log_warning "No krb5.conf backup found"
    fi
}

# ========================
# Test Configuration
# ========================
test_config() {
    echo ""
    log_info "Testing configuration..."

    # Test DNS resolution
    log_info "Testing DNS resolution..."
    if host "$DC_FQDN" "$DNS_IP" &>/dev/null; then
        log_success "DNS resolution working for $DC_FQDN"
    else
        log_warning "DNS resolution failed for $DC_FQDN"
    fi

    # Test Kerberos (if kinit available)
    if command -v klist &> /dev/null; then
        log_info "Current Kerberos tickets:"
        klist 2>/dev/null || echo "  No tickets"
    fi

    echo ""
    log_info "To obtain a Kerberos ticket, run:"
    echo -e "  ${CYAN}kinit username@${DOMAIN^^}${NC}"
    echo ""
    log_info "To verify the ticket:"
    echo -e "  ${CYAN}klist${NC}"
    echo ""
    log_info "To use the ticket with impacket tools:"
    echo -e "  ${CYAN}export KRB5CCNAME=/tmp/krb5cc_\$(id -u)${NC}"
    echo -e "  ${CYAN}impacket-GetUserSPNs -k -no-pass -dc-host $DC_FQDN ${DOMAIN}/username${NC}"
}

# ========================
# Print Current Config
# ========================
print_config() {
    echo ""
    echo -e "${YELLOW}Current Configuration:${NC}"
    echo "  Domain:       $DOMAIN"
    echo "  Realm:        ${DOMAIN^^}"
    echo "  DC IP:        $DC_IP"
    echo "  DC FQDN:      $DC_FQDN"
    echo "  DC NetBIOS:   $DC_NETBIOS"
    echo "  DNS Server:   $DNS_IP"
    echo "  Backup Dir:   $BACKUP_DIR"
    echo ""
}

# ========================
# Main
# ========================

# Parse arguments
SKIP_NTP=false
SKIP_HOSTS=false
SKIP_DNS=false
SKIP_KRB5=false
NTP_ONLY=false
HOSTS_ONLY=false
DNS_ONLY=false
KRB5_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -t|--dc-ip)
            DC_IP="$2"
            shift 2
            ;;
        -n|--dc-name)
            DC_NETBIOS="$2"
            shift 2
            ;;
        -s|--dns-ip)
            DNS_IP="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --restore)
            RESTORE=true
            shift
            ;;
        --ntp-only)
            NTP_ONLY=true
            shift
            ;;
        --hosts-only)
            HOSTS_ONLY=true
            shift
            ;;
        --dns-only)
            DNS_ONLY=true
            shift
            ;;
        --krb5-only)
            KRB5_ONLY=true
            shift
            ;;
        --skip-ntp)
            SKIP_NTP=true
            shift
            ;;
        --skip-hosts)
            SKIP_HOSTS=true
            shift
            ;;
        --skip-dns)
            SKIP_DNS=true
            shift
            ;;
        --skip-krb5)
            SKIP_KRB5=true
            shift
            ;;
        -h|--help)
            print_banner
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Print banner
if [ "$QUIET" = false ]; then
    print_banner
fi

# Handle restore
if [ "$RESTORE" = true ]; then
    check_root
    restore_backups
    exit 0
fi

# Validate required arguments
if [ -z "$DOMAIN" ] || [ -z "$DC_IP" ]; then
    log_error "Domain (-d) and DC IP (-t) are required"
    echo ""
    usage
fi

# Check root
check_root

# Check dependencies
check_dependencies

# Detect DC info
detect_dc_info

# Print config
if [ "$QUIET" = false ]; then
    print_config
fi

# Create backup directory
create_backup_dir

# Dry run notice
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                    DRY RUN MODE                           ${NC}"
    echo -e "${YELLOW}         No changes will be made to the system             ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
fi

# Execute based on options
if [ "$NTP_ONLY" = true ]; then
    sync_ntp
elif [ "$HOSTS_ONLY" = true ]; then
    update_hosts
elif [ "$DNS_ONLY" = true ]; then
    update_resolv
elif [ "$KRB5_ONLY" = true ]; then
    update_krb5
else
    # Full setup
    [ "$SKIP_NTP" = false ] && sync_ntp
    [ "$SKIP_HOSTS" = false ] && update_hosts
    [ "$SKIP_DNS" = false ] && update_resolv
    [ "$SKIP_KRB5" = false ] && update_krb5
fi

# Test configuration (unless dry run)
if [ "$DRY_RUN" = false ]; then
    test_config
fi

echo ""
log_success "Kerberos setup complete!"
