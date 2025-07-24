#!/bin/bash
# Check for required commands
for cmd in gcloud ssh-keygen openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[-] Error: Required command '$cmd' not found."
    echo "    Please install it and try again."
    exit 1
  fi
done

# Set variables (customize these)
read -p "Enter your Google Cloud Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
  echo "[-] Error: Project ID is required"
  exit 1
fi

INSTANCE_NAME="syncthing-instance"
ZONE="us-central1-a"
STATIC_IP_NAME="syncthing-ip"
TAG="syncthing"

# Check if logged in to Google Cloud CLI
echo "[+] Checking if you're logged in to Google Cloud CLI..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
  echo "[-] Error: You are not logged in to Google Cloud CLI. Please run 'gcloud auth login' first."
  exit 1 
fi
echo "[+] You are logged in to Google Cloud CLI."

# Check if project exists
echo "[+] Checking if project $PROJECT_ID exists..."
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  echo "[-] Error: Project $PROJECT_ID does not exist or you don't have access to it."
  echo "    Please check the project ID or create the project with: gcloud projects create $PROJECT_ID"
  exit 1
fi
echo "[+] Project $PROJECT_ID exists."

# Confirm resource creation
echo "This script will create the following resources in project '$PROJECT_ID':"
echo "  - A VM instance (e2-micro) named 'syncthing-instance'"
echo "  - A static IP address named 'syncthing-ip'"
echo "  - Firewall rules for Syncthing (ports 8384, 22000, 21027)"
echo "  - Docker containers for Syncthing within syncthing-instance"
read -p "Do you want to proceed? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Deployment canceled."
  exit 0
fi

# Set the project for all gcloud commands
gcloud config set project "$PROJECT_ID"

# Enable required Google Cloud APIs
echo "[+] Checking if Compute Engine API is enabled..."
if ! gcloud services list --enabled | grep -q "compute.googleapis.com"; then
  echo "[+] Enabling Compute Engine API (this may take a few minutes)..."
  gcloud services enable compute.googleapis.com
  
  # Wait for API to be fully enabled
  echo "[+] Waiting for Compute Engine API to be fully enabled..."
  while ! gcloud services list --enabled | grep -q "compute.googleapis.com"; do
    echo "[+] Still waiting for Compute Engine API to be enabled..."
    sleep 10
  done
  echo "[+] Compute Engine API enabled successfully!"
else
  echo "[+] Compute Engine API is already enabled."
fi

# Extract region from zone
REGION="${ZONE%-*}"

# Generate a dedicated SSH key for this script without passphrase
# Store it in a permanent location
SSH_KEY_DIR="$HOME/.ssh/syncthing-deployment"
SSH_KEY_PATH="$SSH_KEY_DIR/syncthing_deploy_key"

# Create directory if it doesn't exist
if [ ! -d "$SSH_KEY_DIR" ]; then
  echo "[+] Creating directory for SSH keys: $SSH_KEY_DIR"
  mkdir -p "$SSH_KEY_DIR"
  chmod 700 "$SSH_KEY_DIR"
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[+] Generating SSH key for deployment at $SSH_KEY_PATH"
  ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -N ""
  # Use a temporary file for the metadata
  SSH_TEMP_FILE=$(mktemp)
  echo "ubuntu:$(cat $SSH_KEY_PATH.pub)" > "$SSH_TEMP_FILE"
  
  # Add the key to the project metadata
  echo "[+] Adding SSH key to project metadata"
  gcloud compute project-info add-metadata --metadata-from-file=ssh-keys="$SSH_TEMP_FILE"
  
  # Clean up the temporary file
  rm -f "$SSH_TEMP_FILE"
  
  # Wait for key to propagate
  echo "[+] Waiting for SSH key to propagate..."
  sleep 15
fi

echo "[+] Checking if static IP address already exists: $STATIC_IP_NAME"
if ! gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
  echo "[+] Creating static IP address: $STATIC_IP_NAME"
  gcloud compute addresses create "$STATIC_IP_NAME" --region="$REGION" || {
    echo "[-] Failed to create static IP address"
    exit 1
  }
fi

echo "[+] Retrieving static IP address"
IP_ADDRESS=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="value(address)")
if [ -z "$IP_ADDRESS" ]; then
  echo "[-] Failed to get IP address"
  exit 1
fi
echo "[+] Static IP address: $IP_ADDRESS"

echo "[+] Checking if instance $INSTANCE_NAME already exists"
if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
  echo "[+] Creating instance $INSTANCE_NAME with static IP, tag, and 30GB disk"
  gcloud compute instances create "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --machine-type=e2-micro \
    --network-tier=PREMIUM \
    --tags="$TAG" \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --address="$IP_ADDRESS" \
    --boot-disk-size=30GB \
    --boot-disk-type=pd-standard \
    --metadata="ssh-keys=ubuntu:$(cat $SSH_KEY_PATH.pub)" || {
      echo "[-] Failed to create instance"
      exit 1
    }
else
  echo "[+] Instance already exists"
  
  # Add SSH key to the existing instance
  SSH_TEMP_FILE=$(mktemp)
  echo "ubuntu:$(cat $SSH_KEY_PATH.pub)" > "$SSH_TEMP_FILE"
  
  echo "[+] Adding SSH key to instance metadata"
  gcloud compute instances add-metadata "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --metadata-from-file=ssh-keys="$SSH_TEMP_FILE"
  
  rm -f "$SSH_TEMP_FILE"
fi

echo "[+] Checking and creating firewall rules for Syncthing"
# Check and create firewall rules
for RULE_NAME in syncthing-webui syncthing-sync syncthing-discovery; do
  if ! gcloud compute firewall-rules describe "$RULE_NAME" &>/dev/null; then
    case "$RULE_NAME" in
      "syncthing-webui")
        echo "[+] Creating firewall rule: $RULE_NAME"
        gcloud compute firewall-rules create "$RULE_NAME" \
          --direction=INGRESS \
          --priority=1000 \
          --network=default \
          --action=ALLOW \
          --rules=tcp:8384 \
          --target-tags="$TAG"
        ;;
      "syncthing-sync")
        echo "[+] Creating firewall rule: $RULE_NAME"
        gcloud compute firewall-rules create "$RULE_NAME" \
          --direction=INGRESS \
          --priority=1000 \
          --network=default \
          --action=ALLOW \
          --rules=tcp:22000 \
          --target-tags="$TAG"
        ;;
      "syncthing-discovery")
        echo "[+] Creating firewall rule: $RULE_NAME"
        gcloud compute firewall-rules create "$RULE_NAME" \
          --direction=INGRESS \
          --priority=1000 \
          --network=default \
          --action=ALLOW \
          --rules=udp:21027 \
          --target-tags="$TAG"
        ;;
    esac
  else
    echo "[+] Firewall rule already exists: $RULE_NAME"
  fi
done

echo "[+] Waiting 60 seconds for instance to be fully ready and SSH to become available..."
sleep 60

echo "[+] SSH into instance and deploy Syncthing"
# Create the remote script as a local file first
cat > /tmp/deploy_syncthing.sh << 'EOF'
#!/bin/bash
# Enable verbose mode for better logging
set -x

# Save external variables from parent script
EXTERNAL_IP="%IP_ADDRESS%"
SYNCTHING_USER="%USERNAME%"
SYNCTHING_PASSWORD="%PASSWORD%"

echo "[+] Starting deployment with these details:"
echo "External IP: $EXTERNAL_IP"
echo "Username: $SYNCTHING_USER"

echo "[+] Checking if running processes might interfere with installation"
ps aux | grep apt
ps aux | grep dpkg

echo "[+] Removing Google Cloud CLI to improve e2-micro performance"
# Force kill any running apt/dpkg processes
sudo killall -9 apt apt-get dpkg 2>/dev/null || true

# Remove any locks
sudo rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true

# Force dpkg to reconfigure
sudo dpkg --configure -a

# Aggressively remove Google Cloud CLI directories first
echo "[+] Directly removing Google Cloud SDK directories"
sudo rm -rf /usr/share/google-cloud-sdk /usr/lib/google-cloud-sdk /opt/google-cloud-sdk 2>/dev/null || true

# Force remove from package system with safeguards
echo "[+] Force-removing Google Cloud CLI packages"
for pkg in google-cloud-cli google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin google-cloud-sdk-app-engine-python google-cloud-sdk-app-engine-python-extras \
google-cloud-sdk-app-engine-java google-cloud-sdk-app-engine-go google-cloud-sdk-bigtable-emulator google-cloud-sdk-cbt google-cloud-sdk-cloud-build-local \
google-cloud-sdk-datastore-emulator google-cloud-sdk-firestore-emulator google-cloud-sdk-pubsub-emulator google-cloud-sdk-spanner-emulator \
google-cloud-sdk-local-extract; do
  sudo dpkg --force-all --remove $pkg 2>/dev/null || true
done

sudo apt-get remove --purge -y 'google-cloud-*' 2>/dev/null || true
sudo apt-get autoremove -y || true

echo "[+] Cleaning up package system"
sudo apt-get clean
sudo apt-get update || { 
  echo "[-] Failed to update package lists, retrying after cleaning sources"
  sudo rm -rf /var/lib/apt/lists/*
  sudo apt-get update
}

# Function to retry commands with backoff
retry_with_backoff() {
  local max_attempts=5
  local timeout=1
  local attempt=1
  local exitCode=0

  while [[ $attempt -le $max_attempts ]]
  do
    echo "[+] Attempt $attempt of $max_attempts: $@"
    "$@"
    exitCode=$?

    if [[ $exitCode == 0 ]]
    then
      echo "[+] Command succeeded."
      return 0
    fi

    echo "[-] Command failed with exit code $exitCode. Retrying in $timeout seconds..."
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  echo "[-] Command failed after $max_attempts attempts."
  return $exitCode
}

echo "[+] Update system and install dependencies"
retry_with_backoff sudo apt-get update -y
retry_with_backoff sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
retry_with_backoff sudo apt-get install -y curl

echo "[+] Installing Docker"
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  if [ $? -ne 0 ]; then
    echo "[-] Docker installation failed. Attempting alternative installation method."
    retry_with_backoff sudo apt-get install -y docker.io
  fi
else
  echo "[+] Docker is already installed"
fi

echo "[+] Enabling Docker service"
sudo systemctl enable docker
sudo systemctl start docker

echo "[+] Verifying Docker installation"
if ! sudo docker --version; then
  echo "[-] Docker installation failed"
  exit 1
fi

echo "[+] Installing Docker Compose"
if ! command -v docker-compose &> /dev/null; then
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  if [ $? -ne 0 ]; then
    echo "[-] Failed to download latest Docker Compose. Trying alternative location."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  fi
  sudo chmod +x /usr/local/bin/docker-compose
else
  echo "[+] Docker Compose is already installed"
fi

echo "[+] Verifying Docker Compose installation"
if ! sudo /usr/local/bin/docker-compose --version; then
  echo "[-] Docker Compose installation failed"
  exit 1
fi

echo "[+] Creating directories for Syncthing"
sudo mkdir -p /opt/syncthing/config /opt/syncthing/data
sudo chmod -R 775 /opt/syncthing

echo "[+] Creating Docker Compose file"
cat <<'DOCKER_COMPOSE' > /tmp/docker-compose.yml
version: '3.8'
services:
  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    environment:
      - PUID=0
      - PGID=0
      - GUI_USER=${SYNCTHING_USER}
      - GUI_PASSWORD=${SYNCTHING_PASSWORD}
    volumes:
      - /opt/syncthing/config:/config
      - /opt/syncthing/data:/data
    ports:
      - 8384:8384
      - 22000:22000/tcp
      - 21027:21027/udp
    restart: unless-stopped
    user: root
DOCKER_COMPOSE

sudo mv /tmp/docker-compose.yml /opt/syncthing/docker-compose.yml

echo "[+] Setting environment variables for Docker Compose"
cat > /tmp/syncthing.env << ENV
SYNCTHING_USER=$SYNCTHING_USER
SYNCTHING_PASSWORD=$SYNCTHING_PASSWORD
ENV
sudo mv /tmp/syncthing.env /opt/syncthing/.env

echo "[+] Checking Docker Compose file contents"
cat /opt/syncthing/docker-compose.yml

echo "[+] Starting Syncthing"
cd /opt/syncthing
if ! sudo /usr/local/bin/docker-compose --env-file .env up -d; then
  echo "[-] Failed to start Syncthing container. Checking logs:"
  sudo /usr/local/bin/docker-compose logs
  exit 1
fi

echo "[+] Verifying Syncthing container is running"
if ! sudo docker ps | grep syncthing; then
  echo "[-] Syncthing container is not running. Checking logs:"
  sudo docker logs syncthing
  exit 1
fi

echo "=============================================="
echo "Syncthing deployment complete!"
echo "Web UI: https://$EXTERNAL_IP:8384"
echo "Username: $SYNCTHING_USER"
echo "Password: $SYNCTHING_PASSWORD"
echo "=============================================="

# Check disk space after installation
echo "[+] Checking disk space"
df -h

# Check memory usage
echo "[+] Checking memory usage"
free -m

# Create a simple service check script
echo "[+] Creating service check script"
cat <<'CHECKSCRIPT' > /tmp/check_syncthing.sh
#!/bin/bash
if ! docker ps | grep -q syncthing; then
  echo "Syncthing container is not running. Restarting..."
  cd /opt/syncthing && docker-compose --env-file .env up -d
  echo "Restarted at $(date)" >> /opt/syncthing/restart.log
fi
CHECKSCRIPT

sudo mv /tmp/check_syncthing.sh /opt/syncthing/check_syncthing.sh
sudo chmod +x /opt/syncthing/check_syncthing.sh

# Set up a cron job to check if the service is running
echo "[+] Setting up monitoring cron job"
(crontab -l 2>/dev/null; echo "*/10 * * * * /opt/syncthing/check_syncthing.sh") | sort | uniq | crontab -

echo "[+] All done! Syncthing is deployed and configured."
EOF

# Replace placeholders with actual values - cross-platform compatible version
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|%IP_ADDRESS%|$IP_ADDRESS|g" /tmp/deploy_syncthing.sh
else
  # Linux/others
  sed -i "s|%IP_ADDRESS%|$IP_ADDRESS|g" /tmp/deploy_syncthing.sh
fi

# Try to connect first to ensure the connection works
echo "[+] Testing SSH connection to the VM"
if ! ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@$IP_ADDRESS" echo "SSH connection test successful"; then
  echo "[-] SSH connection test failed. Checking VM status and trying alternative user..."
  gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)"
  
  # Try with default 'ubuntu' username
  if ! ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@$IP_ADDRESS" echo "SSH connection test successful"; then
    echo "[-] SSH connection still failing. Please check your VM and SSH keys."
    exit 1
  fi
fi

# Copy the script to the VM and execute it using our custom SSH key
echo "[+] Copying deployment script to VM"
gcloud compute scp --ssh-key-file="$SSH_KEY_PATH" "/tmp/deploy_syncthing.sh" "ubuntu@${INSTANCE_NAME}:/tmp/deploy_syncthing.sh" --zone="$ZONE" || {
  echo "[-] Failed to copy deployment script to VM"
  echo "Troubleshooting: Trying to connect with verbose output..."
  ssh -v -i "$SSH_KEY_PATH" "ubuntu@$IP_ADDRESS" echo "Test connection"
  exit 1
}

# Execute the script on the VM
echo "[+] Executing deployment script on VM"
gcloud compute ssh --ssh-key-file="$SSH_KEY_PATH" "ubuntu@$INSTANCE_NAME" --zone="$ZONE" --command="chmod +x /tmp/deploy_syncthing.sh && sudo /tmp/deploy_syncthing.sh" || {
  echo "[-] Failed to execute deployment script on VM"
  exit 1
}

# Clean up temporary files
rm -f /tmp/deploy_syncthing.sh

# Output final details
echo
echo "=============================================="
echo "[+] Deployment complete! Syncthing should now be running."
echo "[!] It is recommended to set this instance as "Untrusted" on other instances"
echo "[!] This will encrypt the files. Better to be safe"
echo "[+] Web UI: https://$IP_ADDRESS:8384"
echo "[+] No credentials have been set - you'll need to configure these"
echo "[+] on your first login to the Syncthing web interface. Do it NOW!"
echo "[+] SSH key location: $SSH_KEY_PATH"
echo "[+] To connect to the VM in the future: ssh -i $SSH_KEY_PATH ubuntu@$IP_ADDRESS"
echo "=============================================="
