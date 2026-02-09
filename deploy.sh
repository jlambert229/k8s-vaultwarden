#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-security}"
RELEASE_NAME="${RELEASE_NAME:-vaultwarden}"

echo "=== Deploying Vaultwarden Password Manager ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

step() {
    echo -e "${GREEN}==>${NC} $1"
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

fail() {
    echo -e "${RED}❌${NC} $1"
    exit 1
}

warn() {
    echo -e "${RED}⚠️${NC} $1"
}

# Check prerequisites
step "Checking prerequisites"

if ! command -v kubectl &> /dev/null; then
    fail "kubectl not found. Please install kubectl."
fi

if ! command -v helm &> /dev/null; then
    fail "helm not found. Please install helm."
fi

if ! kubectl cluster-info &> /dev/null; then
    fail "Cannot connect to Kubernetes cluster. Check your KUBECONFIG."
fi

echo "✅ Prerequisites met"
echo ""

# Add Helm repo
step "Adding bjw-s Helm repository"
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts/ 2>/dev/null || true
helm repo update bjw-s
echo ""

# Create namespace
step "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo ""

# Security warning
warn "SECURITY NOTICE"
echo ""
echo "Vaultwarden stores your passwords. Please ensure:"
echo "  1. HTTPS is enabled (Bitwarden clients require TLS)"
echo "  2. Regular backups are configured (./backup.sh)"
echo "  3. Signups are disabled after creating your account"
echo "  4. Admin token is set or admin panel is disabled"
echo ""
read -p "Continue with deployment? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Deploy Vaultwarden
step "Deploying Vaultwarden"
helm upgrade --install "$RELEASE_NAME" bjw-s/app-template \
    --namespace "$NAMESPACE" \
    --values values.yaml \
    --wait \
    --timeout 5m
echo ""

# Wait for pod to be ready
step "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=vaultwarden \
    -n "$NAMESPACE" \
    --timeout=300s
echo ""

# Get ingress info
step "Deployment complete!"
echo ""
echo "✅ Vaultwarden is now running."
echo ""
echo "Access the web UI:"
INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app.kubernetes.io/name=vaultwarden -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "vault.media.lan")
echo "  https://$INGRESS_HOST"
echo ""
warn "IMPORTANT: First-time setup"
echo ""
echo "1. Create your admin account (first user)"
echo "   - Open https://$INGRESS_HOST"
echo "   - Click 'Create Account'"
echo "   - WRITE DOWN your master password (no recovery if lost!)"
echo ""
echo "2. Disable public signups"
echo "   - Edit values.yaml: SIGNUPS_ALLOWED: \"false\""
echo "   - Redeploy: ./deploy.sh"
echo ""
echo "3. Configure browser extension"
echo "   - Install Bitwarden extension"
echo "   - Settings → Server URL: https://$INGRESS_HOST"
echo "   - Log in"
echo ""
echo "4. Set up backups"
echo "   - Run: ./backup.sh"
echo "   - Add to cron: 0 4 * * * /path/to/backup.sh"
echo ""
echo "5. Enable 2FA"
echo "   - Web vault → Settings → Two-step Login"
echo "   - Use authenticator app or hardware key"
echo ""
echo "Check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=vaultwarden"
