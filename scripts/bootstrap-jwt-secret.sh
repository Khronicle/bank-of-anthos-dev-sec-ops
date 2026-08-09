#!/bin/bash
# Run ONCE on the k3s node itself, via SSM Session Manager — never over SSH,
# never from a laptop, never through GitHub Actions. The private key this
# generates must not transit any network or CI log; running it locally on the
# box is what guarantees that.
#
# Usage (from a team member's machine, after `aws configure`):
#   aws ssm start-session --target <instance-id>
#   sudo bash /opt/bank-of-anthos/bootstrap-jwt-secret.sh
#
# Idempotent: does nothing if the jwt-key Secret already exists.
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NAMESPACE=bank-of-anthos

if kubectl -n "$NAMESPACE" get secret jwt-key >/dev/null 2>&1; then
  echo "jwt-key Secret already exists in namespace $NAMESPACE — nothing to do."
  exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

openssl genrsa -out "$WORKDIR/jwtRS256.key" 4096
openssl rsa -in "$WORKDIR/jwtRS256.key" -outform PEM -pubout -out "$WORKDIR/jwtRS256.key.pub"

kubectl -n "$NAMESPACE" create secret generic jwt-key \
  --from-file="$WORKDIR/jwtRS256.key" \
  --from-file="$WORKDIR/jwtRS256.key.pub"

echo "jwt-key Secret created in namespace $NAMESPACE."
