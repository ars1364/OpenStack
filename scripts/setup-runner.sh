#!/usr/bin/env bash
# Register a GitHub Actions self-hosted runner.
#
# Usage:
#   ./setup-runner.sh <GITHUB_PAT> <REPO> [RUNNER_NAME] [LABELS]
#
# Example:
#   ./setup-runner.sh ghp_xxx ars1364/keemiya-website keemiyamahour "self-hosted,linux,x64,openstack"
#
# This script is idempotent — it skips registration if the runner
# is already configured.

set -euo pipefail

GITHUB_PAT="${1:?Usage: $0 <GITHUB_PAT> <REPO> [RUNNER_NAME] [LABELS]}"
REPO="${2:?Usage: $0 <GITHUB_PAT> <REPO> [RUNNER_NAME] [LABELS]}"
RUNNER_NAME="${3:-$(hostname)}"
LABELS="${4:-self-hosted,linux,x64,openstack}"
RUNNER_DIR="/data/actions-runner"

cd "$RUNNER_DIR"

# Skip if already configured
if [[ -f .runner ]]; then
  echo "Runner already configured. To reconfigure, remove .runner first."
  exit 0
fi

# Get a registration token from GitHub API
echo "Fetching registration token for $REPO..."
REG_TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/actions/runners/registration-token" \
  | jq -r .token)

if [[ "$REG_TOKEN" == "null" || -z "$REG_TOKEN" ]]; then
  echo "ERROR: Failed to get registration token. Check your PAT permissions." >&2
  exit 1
fi

# Configure the runner (non-interactive)
./config.sh \
  --url "https://github.com/$REPO" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$LABELS" \
  --work "_work" \
  --unattended \
  --replace

# Install and start as a systemd service
echo "Installing runner service..."
sudo ./svc.sh install ubuntu
sudo ./svc.sh start

echo ""
echo "Runner '$RUNNER_NAME' registered and running for $REPO"
echo "Labels: $LABELS"
echo "Service: actions.runner.${REPO//\//-}.$RUNNER_NAME.service"
