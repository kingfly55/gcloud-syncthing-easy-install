#!/bin/bash

# Cleanup script for Syncthing deployment on Google Cloud
# Removes all resources created by the installation script

echo "[+] Starting Syncthing deployment cleanup..."

# Set variables (must match the installation script)
INSTANCE_NAME="syncthing-instance"
ZONE="us-central1-a"
STATIC_IP_NAME="syncthing-ip"
TAG="syncthing"
REGION="${ZONE%-*}"

# Check for required commands
for cmd in gcloud; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[-] Error: Required command '$cmd' not found."
    echo "    Please install it and try again."
    exit 1
  fi
done

# Check if logged in to Google Cloud CLI
echo "[+] Checking if you're logged in to Google Cloud CLI..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
  echo "[-] Error: You are not logged in to Google Cloud CLI. Please run 'gcloud auth login' first."
  exit 1 
fi
echo "[+] You are logged in to Google Cloud CLI."

# Get project ID
read -p "Enter your Google Cloud Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
  echo "[-] Error: Project ID is required"
  exit 1
fi

# Check if project exists
echo "[+] Checking if project $PROJECT_ID exists..."
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  echo "[-] Error: Project $PROJECT_ID does not exist or you don't have access to it."
  exit 1
fi
echo "[+] Project $PROJECT_ID exists."

# Set the project for all gcloud commands
gcloud config set project "$PROJECT_ID"

# Confirm deletion
echo "This script will delete the following resources from project '$PROJECT_ID':"
echo "  - VM instance named '$INSTANCE_NAME'"
echo "  - Static IP address named '$STATIC_IP_NAME'"
echo "  - Firewall rules: syncthing-webui, syncthing-sync, syncthing-discovery"
echo "  - SSH keys added to project metadata"
read -p "Are you sure you want to proceed? This action is irreversible. (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Cleanup canceled."
  exit 0
fi

# Delete instance
echo "[+] Checking if instance $INSTANCE_NAME exists"
if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
  echo "[+] Deleting instance $INSTANCE_NAME"
  gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet || {
    echo "[-] Failed to delete instance"
  }
else
  echo "[+] Instance $INSTANCE_NAME does not exist"
fi

# Delete static IP address
echo "[+] Checking if static IP address $STATIC_IP_NAME exists"
if gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
  echo "[+] Deleting static IP address $STATIC_IP_NAME"
  gcloud compute addresses delete "$STATIC_IP_NAME" --region="$REGION" --quiet || {
    echo "[-] Failed to delete static IP address"
  }
else
  echo "[+] Static IP address $STATIC_IP_NAME does not exist"
fi

# Delete firewall rules
for RULE_NAME in syncthing-webui syncthing-sync syncthing-discovery; do
  echo "[+] Checking if firewall rule $RULE_NAME exists"
  if gcloud compute firewall-rules describe "$RULE_NAME" &>/dev/null; then
    echo "[+] Deleting firewall rule $RULE_NAME"
    gcloud compute firewall-rules delete "$RULE_NAME" --quiet || {
      echo "[-] Failed to delete firewall rule $RULE_NAME"
    }
  else
    echo "[+] Firewall rule $RULE_NAME does not exist"
  fi
done

# Remove SSH keys from project metadata
echo "[+] Attempting to remove SSH keys from project metadata"
echo "[!] Note: Google Cloud doesn't provide a direct way to remove specific SSH keys."
echo "[!] You may need to manually clean up SSH keys in the Google Cloud Console:"
echo "[!] 1. Go to Compute Engine > Metadata > SSH Keys"
echo "[!] 2. Remove the key for 'ubuntu' user that was added by the installation script"

# SSH key location information
SSH_KEY_DIR="$HOME/.ssh/syncthing-deployment"
echo "[+] SSH keys are located at: $SSH_KEY_DIR"
echo "[!] To completely remove the keys from your local machine, run:"
echo "[!]   rm -rf $SSH_KEY_DIR"

echo
echo "=============================================="
echo "[+] Cleanup process completed!"
echo "[+] Please verify that all resources have been removed:"
echo "[+]   - Instance: gcloud compute instances list --filter='name=$INSTANCE_NAME'"
echo "[+]   - IP Address: gcloud compute addresses list --filter='name=$STATIC_IP_NAME'"
echo "[+]   - Firewall rules: gcloud compute firewall-rules list --filter='name~syncthing'"
echo "[!] Remember to manually check and remove any SSH keys from project metadata"
echo "=============================================="
