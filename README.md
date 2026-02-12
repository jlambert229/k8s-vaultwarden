# k8s-vaultwarden

![pre-commit](https://github.com/jlambert229/k8s-vaultwarden/actions/workflows/pre-commit.yml/badge.svg)
![GitHub last commit](https://img.shields.io/github/last-commit/jlambert229/k8s-vaultwarden)

Self-hosted password manager using [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (Bitwarden-compatible server) on Kubernetes.

**Blog post:** [Self-Hosted Password Manager with Vaultwarden](https://foggyclouds.io/post/vaultwarden-self-hosted-passwords/)

## Features

- **Bitwarden-compatible** - Works with official Bitwarden browser extensions, mobile apps, desktop clients
- **Self-hosted** - Your passwords stay on your infrastructure
- **TOTP 2FA** - Built-in authenticator (no separate app needed)
- **Secure notes** - Store SSH keys, API tokens, recovery codes
- **Emergency access** - Designate trusted contacts for account recovery
- **Zero subscription fees** - Unlike 1Password/Bitwarden cloud

## ⚠️ Security Warning

This deployment stores your password vault. Take security seriously:

- **HTTPS is mandatory** - Bitwarden clients refuse HTTP connections
- **Regular backups** - Losing the database = losing all passwords
- **Disable signups** - After creating your account
- **Strong master password** - Use diceware (6+ words) and write it down
- **Off-site backups** - Don't store only backups on the same server

## Prerequisites

- Kubernetes cluster (tested on Talos)
- Helm 3.x
- Traefik ingress controller
- cert-manager for TLS certificates
- NFS CSI driver with `nfs-appdata` StorageClass
- DNS entry: `vault.media.lan → <TRAEFIK_IP>`

## Quick Start

```bash
# Clone the repo
git clone https://github.com/YOUR-USERNAME/k8s-vaultwarden.git
cd k8s-vaultwarden

# Deploy
./deploy.sh

# Access the web UI
open https://vault.media.lan
```

## First-Time Setup

### 1. Create Your Account

1. Open `https://vault.media.lan`
2. Click "Create Account"
3. Enter email and **strong master password**
   - Use diceware: 6+ random words
   - Example: `correct-horse-battery-staple-mountain-river`
   - **Write it down on paper** - no recovery if lost!
4. Create account

### 2. Disable Public Signups

After creating your account, prevent others from signing up:

```bash
# Edit values.yaml
SIGNUPS_ALLOWED: "false"

# Redeploy
./deploy.sh
```

### 3. Configure Browser Extension

Install Bitwarden extension:
- [Chrome Web Store](https://chrome.google.com/webstore/detail/bitwarden/nngceckbapebfimnlniiiahkandclblb)
- [Firefox Add-ons](https://addons.mozilla.org/en-US/firefox/addon/bitwarden-password-manager/)

Configure:
1. Extension settings (gear icon)
2. Server URL: `https://vault.media.lan`
3. Log in

### 4. Install Mobile Apps

- **iOS:** [App Store](https://apps.apple.com/app/bitwarden-password-manager/id1137397744)
- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.x8bit.bitwarden)

On first launch:
1. Tap "Self-hosted"
2. Server URL: `https://vault.media.lan`
3. Log in

### 5. Enable 2FA (Recommended)

Web vault → Settings → Two-step Login

**Authenticator app (TOTP):**
1. Click "Manage" next to "Authenticator App"
2. Scan QR code with Vaultwarden's built-in TOTP or external app
3. Save recovery code

**Hardware key (YubiKey):**
1. Settings → Two-step Login → FIDO2 WebAuthn
2. Insert YubiKey, click "Add"

### 6. Set Up Backups

**Critical:** Your password vault is in a single SQLite database.

```bash
# Manual backup
./backup.sh

# Automate with cron
0 4 * * * /path/to/k8s-vaultwarden/backup.sh 2>&1 | logger -t vaultwarden-backup

# Off-site sync
rsync -avz ./backups/ user@nas:/backups/vaultwarden/
```

## Configuration

### values.yaml

Edit to customize:

- **DOMAIN** - Must match ingress hostname (used for email links)
- **SIGNUPS_ALLOWED** - Set to `"false"` after account creation
- **ADMIN_TOKEN** - Secure admin panel (generate: `openssl rand -base64 48`)
- **TZ** - Your timezone
- **Storage size** - PVC size (default 1Gi)
- **cert-manager issuer** - `selfsigned-ca` or `letsencrypt-prod`

### Admin Panel

Access: `https://vault.media.lan/admin`

**Secure it:**

```yaml
# values.yaml
env:
  ADMIN_TOKEN: "<output-of-openssl-rand-base64-48>"
```

Or disable completely:

```yaml
env:
  ADMIN_TOKEN: "disabled"
```

## Import Existing Passwords

### From 1Password

1. 1Password → File → Export → CSV
2. Vaultwarden → Settings → Import Data → "1Password (csv)"
3. Upload file
4. Delete CSV from disk

### From Bitwarden Cloud

1. Bitwarden → Settings → Export Vault → JSON
2. Vaultwarden → Import Data → "Bitwarden (json)"
3. Upload and delete export

### From Chrome/Firefox

1. Browser → Settings → Passwords → Export
2. Vaultwarden → Import Data → "Chrome (csv)"
3. Upload and delete CSV

## Backups

**Critical:** Losing the database = losing all passwords.

### Automated Backups

```bash
./backup.sh
```

- SQLite database backup (proper `.backup` command)
- Attachments backup (if any)
- Keeps last 30 backups
- Stores in `./backups/`

### Off-Site Storage

**Do not** store backups only on the same server as Vaultwarden.

```bash
# Sync to NAS
rsync -avz ./backups/ youruser@192.168.1.10:/volume1/backups/vaultwarden/

# Encrypt and upload to cloud
gpg -c ./backups/vaultwarden-20260208_040000.db
rclone copy ./backups/vaultwarden-20260208_040000.db.gpg remote:vaultwarden/
```

### Restore

```bash
# 1. Scale down
kubectl scale -n security deploy/vaultwarden --replicas=0

# 2. Copy backup to pod
kubectl cp ./backups/vaultwarden-20260208_040000.db security/<pod>:/data/db.sqlite3

# 3. Scale up
kubectl scale -n security deploy/vaultwarden --replicas=1
```

## Usage Tips

### TOTP 2FA in Vaultwarden

Store TOTP secrets directly (no separate authenticator app):

1. Edit a login item
2. "New Custom Field" → "TOTP"
3. Paste secret key or scan QR code
4. Vaultwarden generates codes automatically

Browser extension shows codes next to passwords.

### Secure Notes

Store SSH keys, API tokens, recovery codes:

1. New Item → Secure Note
2. Paste content
3. Optionally attach files (`.pem`, etc.)

### Emergency Access

Designate a trusted contact who can request access after a waiting period:

1. Settings → Emergency Access
2. Invite Trusted Emergency Contact
3. Set waiting period (e.g., 30 days)

Use case: If you die, spouse can access after 30 days.

## Troubleshooting

### Browser extension won't connect

**HTTPS required.** Bitwarden clients refuse HTTP.

1. Verify cert-manager issued certificate:
   ```bash
   kubectl get certificate -n security
   ```
2. Trust self-signed cert (if using `selfsigned-ca`):
   - Chrome: `chrome://settings/certificates` → Import CA
   - Firefox: `about:preferences#privacy` → Certificates → Import
3. Or use Let's Encrypt with real domain

### Mobile app can't connect

**Check network:**

1. Is phone on same LAN as homelab?
2. Does Pi-hole serve `vault.media.lan` to mobile?
3. Self-signed certs may fail on iOS/Android (use Let's Encrypt)

### Forgot master password

**There is no recovery.** This is by design. Your vault is encrypted with your master password.

**Prevention:**
1. Write master password on paper, store in safe
2. Use Emergency Access (trusted contact)
3. Export vault periodically (Settings → Export Vault → JSON encrypted)

### Database corruption

**Symptom:** Vaultwarden won't start, logs show database errors

**Recovery:**

```bash
kubectl scale -n security deploy/vaultwarden --replicas=0
kubectl cp ./backups/vaultwarden-20260208_040000.db security/<pod>:/data/db.sqlite3
kubectl scale -n security deploy/vaultwarden --replicas=1
```

## Security Hardening

### 1. Disable Signups

```yaml
SIGNUPS_ALLOWED: "false"
INVITATIONS_ALLOWED: "true"  # Only you can invite
```

### 2. Set Admin Token

```yaml
ADMIN_TOKEN: "<openssl-rand-base64-48>"
```

Or disable admin panel:

```yaml
ADMIN_TOKEN: "disabled"
```

### 3. Enable 2FA

Web vault → Settings → Two-step Login → Authenticator App or FIDO2

### 4. Regular Backups

Automate: `0 4 * * * /path/to/backup.sh`

### 5. Off-Site Backups

Rsync to NAS + cloud backup (encrypted)

### 6. Network Isolation

**Do not expose directly to internet** without:
- Cloudflare Tunnel
- VPN (Tailscale/WireGuard)
- fail2ban

## Resource Usage

Tested on 2-worker cluster (2 vCPU, 4 GB RAM per worker):

- **CPU:** <1% idle, <5% during sync
- **Memory:** 80-120 MB
- **Storage:** 50 MB (database + attachments for 500 logins)

## Teardown

```bash
helm uninstall vaultwarden -n security
kubectl delete namespace security
```

⚠️ **Warning:** This does NOT delete PVC data. Backups remain.

## References

- [Vaultwarden GitHub](https://github.com/dani-garcia/vaultwarden)
- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [Bitwarden Clients](https://bitwarden.com/download/)
- [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
- [Blog post: Self-Hosted Password Manager](https://foggyclouds.io/post/vaultwarden-self-hosted-passwords/)

## License

MIT
