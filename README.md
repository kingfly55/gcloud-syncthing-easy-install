# One-Click Syncthing Deployment on Google Cloud Free Tier

🚀 **Simplified Syncthing Deployment**  
This repository provides a fully automated, one-click script to deploy [Syncthing](https://syncthing.net/) on Google Cloud's Free Tier. Syncthing is a continuous file synchronization program that synchronizes files between two or more computers in real time, safely protected from prying eyes.

## Prerequisites 📋
Before running the script, ensure you have:
1. A **Google Cloud Platform (GCP)** account with billing enabled (but no charges for free tier usage).  
2. The **Google Cloud SDK** installed on your local machine.  
3. Basic familiarity with the terminal or command line.  

## Usage 🚀

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/one-click-syncthing-google-cloud.git
cd one-click-syncthing-google-cloud
```

### 2. Run the Installation Script
Execute the installation script:
```bash
chmod +x install_syncthing.sh
./install_syncthing.sh
```

### 3. Follow the Prompts
The script will guide you through the process, including:
- Entering your **Google Cloud Project ID**.  
- Confirming resource creation.  
- Setting up SSH keys.

Note that the setup may take ~30 minutes, as we're running on a VM with very limited resources

### 4. Access Syncthing
After deployment, you’ll see the following details:
- **Web UI:** `https://<your-static-ip>:8384`  
- **SSH Access:** `ssh -i ~/.ssh/syncthing-deployment/syncthing_deploy_key ubuntu@<your-static-ip>`  

--- 
---

## Technical Details ⚙️

### Features ✨
- **Google Cloud Free Tier Support:** Runs on the `e2-micro` instance, ensuring zero cost under the free tier limits.  
- **Docker Deployment:** Uses Docker and Docker Compose for easy management and updates.  
- **Persistent Storage:** Configures a 30GB disk for your Syncthing data.  
- **Static IP Address:** Assigns a static IP for consistent access.  
- **Firewall Rules:** Automatically sets up required firewall rules for Syncthing.  
- **Monitoring:** Includes a cron job to ensure Syncthing is always running.  
- **SSH Key Management:** Generates and manages dedicated SSH keys for secure access.

  
### What the Script Does
1. **Checks Dependencies:** Ensures `gcloud`, `ssh-keygen`, and `openssl` are installed.  
2. **Creates Resources:** Sets up a VM, static IP, firewall rules, and a 30GB disk.  
3. **Deploys Syncthing:** Installs Docker, deploys Syncthing via Docker Compose, and configures access.  
4. **Monitors Service:** Adds a cron job to restart Syncthing if it stops.  

### Included Resources
- **VM Instance:** `e2-micro` machine with Ubuntu 22.04 LTS.  
- **Firewall Rules:** Opens ports `8384` (Web UI), `22000` (Sync), and `21027` (Discovery).  
- **Persistent Disk:** 30GB standard persistent disk.  

## Costs 💰
The deployment uses Google Cloud's Free Tier, which includes:
- **1 `e2-micro` VM** per month in specific regions.  
- **30GB Standard Persistent Disk.**  
- **Static IP** (free as long as the instance is running).  

**Note:** Ensure your usage stays within the free tier limits to avoid charges.  

---

## Troubleshooting 🛠️
If you encounter issues:
### SSH Connection Fails
- Verify the VM is running:  
  ```bash
  gcloud compute instances describe syncthing-instance --zone=us-central1-a
  ```
- Check the SSH key:  
  ```bash
  ssh -vvv -i ~/.ssh/syncthing-deployment/syncthing_deploy_key ubuntu@<your-static-ip>
  ```

### Syncthing Container Not Running
- Check Docker logs:  
  ```bash
  ssh -i ~/.ssh/syncthing-deployment/syncthing_deploy_key ubuntu@<your-static-ip> "sudo docker logs syncthing"
  ```

## Cant fix it?
Try running the cleanup script, and then trying again.

- Submit an issue to this repo with your logs if it doesn't work.

---

## Contributing 🤝
Contributions are welcome! Here are some ideas for improvements:
- [ ] **Auto-configure Web UI credentials**: Print these to the console after deployment is complete
- [ ] **Configure HTTPS**: Get syncthing to run over HTTPS
- [ ] **Port to Alpine Linux:** Use Alpine Linux for reduced resource usage

You could probably one-shot this with qwen3 coder... I'll get around to it eventually but this works well enough for now

---

## License 📄
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.  

## Acknowledgments 👍
- [Syncthing](https://syncthing.net/) for the amazing synchronization tool.  
- [Google Cloud Platform](https://cloud.google.com/) for the free tier offering.  
- The open-source community for inspiration and support.  
