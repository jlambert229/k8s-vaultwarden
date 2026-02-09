#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-security}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Backing up Vaultwarden ==="

# Get pod name
POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$POD" ]]; then
    echo "❌ No Vaultwarden pod found in namespace $NAMESPACE"
    exit 1
fi

echo "Pod: $POD"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup database using SQLite .backup command (proper way)
echo "Backing up database..."
kubectl exec -n "$NAMESPACE" "$POD" -- sqlite3 /data/db.sqlite3 ".backup /tmp/vaultwarden-backup.db" 2>/dev/null || {
    echo "⚠️  SQLite backup command failed, trying file copy..."
    kubectl exec -n "$NAMESPACE" "$POD" -- cp /data/db.sqlite3 /tmp/vaultwarden-backup.db
}
kubectl cp -n "$NAMESPACE" "$POD:/tmp/vaultwarden-backup.db" "$BACKUP_DIR/vaultwarden-${TIMESTAMP}.db"
kubectl exec -n "$NAMESPACE" "$POD" -- rm /tmp/vaultwarden-backup.db

echo "✅ Database backup saved: $BACKUP_DIR/vaultwarden-${TIMESTAMP}.db"

# Backup attachments (if any)
echo "Backing up attachments..."
if kubectl exec -n "$NAMESPACE" "$POD" -- test -d /data/attachments 2>/dev/null; then
    kubectl exec -n "$NAMESPACE" "$POD" -- tar czf /tmp/attachments.tar.gz /data/attachments 2>/dev/null
    kubectl cp -n "$NAMESPACE" "$POD:/tmp/attachments.tar.gz" "$BACKUP_DIR/attachments-${TIMESTAMP}.tar.gz"
    kubectl exec -n "$NAMESPACE" "$POD" -- rm /tmp/attachments.tar.gz
    echo "✅ Attachments backup saved: $BACKUP_DIR/attachments-${TIMESTAMP}.tar.gz"
else
    echo "→ No attachments to backup"
fi

# Get backup sizes
echo ""
DB_SIZE=$(du -h "$BACKUP_DIR/vaultwarden-${TIMESTAMP}.db" | cut -f1)
echo "Backup sizes:"
echo "  Database: $DB_SIZE"
if [[ -f "$BACKUP_DIR/attachments-${TIMESTAMP}.tar.gz" ]]; then
    ATT_SIZE=$(du -h "$BACKUP_DIR/attachments-${TIMESTAMP}.tar.gz" | cut -f1)
    echo "  Attachments: $ATT_SIZE"
fi
echo ""

# Keep last 30 backups
echo "Cleaning old backups (keeping last 30)..."
ls -t "$BACKUP_DIR"/vaultwarden-*.db 2>/dev/null | tail -n +31 | xargs -r rm
ls -t "$BACKUP_DIR"/attachments-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm
REMAINING=$(ls -1 "$BACKUP_DIR"/vaultwarden-*.db 2>/dev/null | wc -l)
echo "✅ Database backups remaining: $REMAINING"
echo ""

echo "=== Backup complete ==="
echo ""
echo "⚠️  IMPORTANT: Store backups off-site!"
echo ""
echo "This database contains your password vault."
echo "Losing it means losing ALL your passwords."
echo ""
echo "Recommended:"
echo "  1. Sync to NAS: rsync -avz ./backups/ user@nas:/backups/vaultwarden/"
echo "  2. Encrypt: gpg -c $BACKUP_DIR/vaultwarden-${TIMESTAMP}.db"
echo "  3. Upload to cloud: rclone copy ./backups remote:vaultwarden/"
echo ""
echo "To restore:"
echo "  1. Scale down: kubectl scale -n $NAMESPACE deploy/vaultwarden --replicas=0"
echo "  2. Copy backup: kubectl cp $BACKUP_DIR/vaultwarden-${TIMESTAMP}.db $NAMESPACE/<pod>:/data/db.sqlite3"
echo "  3. Scale up: kubectl scale -n $NAMESPACE deploy/vaultwarden --replicas=1"
