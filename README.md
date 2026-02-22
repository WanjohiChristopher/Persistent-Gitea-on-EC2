# Persistent Gitea on EC2 (Docker + EBS + S3 Backup)

**Cloud Computing:** 

---

## Architecture Summary

This deployment runs Gitea, a self-hosted Git service inside a Docker container on a single AWS EC2 instance (Ubuntu). All application data is stored on a dedicated EBS volume mounted at `~/data` on the host, which is bind-mounted into the container at `/data`. This separates compute (EC2/Docker) from state (EBS), meaning the container can be stopped, deleted, and recreated without any data loss. A backup workflow uses the AWS CLI to compress the EBS-backed data directory into a `.tar.gz` archive and upload it to an S3 bucket, providing an offsite recovery point independent of both the EC2 instance and the EBS volume.

---
## Architecture
![Architecturte](gitea-architecture.svg)

## Deployment Instructions

### 1. Provision EC2

Launch an Ubuntu 22.04 LTS EC2 instance. Configure the Security Group:

| Port | Protocol | Source |
|------|----------|--------|
| 22   | TCP | Your IP only |
| 3000 | TCP | 0.0.0.0/0 |

SSH into the instance (Mac):

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>

```


### 2. Create and Attach an EBS Volume

In the AWS Console → EC2 → Elastic Block Store → Volumes → **Create Volume**. Choose the **same Availability Zone** as your EC2 instance, then attach it.

### 3. Format and Mount the EBS Volume

```bash
sudo lsblk                              # identify the new device e.g. nvme1n1
sudo mkfs.ext4 /dev/nvme1n1            # format as ext4
mkdir -p ~/data
sudo mount /dev/nvme1n1 ~/data
sudo chown -R ubuntu:ubuntu ~/data
df -h                                   # confirm mount
```

### 4. Make the Mount Persistent

```bash
sudo blkid                              # copy the UUID for nvme1n1
sudo nano /etc/fstab
```

Add this line (replace UUID with yours):
```
UUID=your-uuid-here /home/ubuntu/data ext4 defaults,nofail 0 2
```

```bash
sudo mount -a                           # test — should return no errors
sudo reboot                             # verify it survives reboot
df -h                                   # ~/data should still be mounted
```

### 5. Install Docker

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
```

### 6. Run Gitea

```bash
git clone https://github.com/<your-username>/gitea-ebs-s3.git
cd gitea-ebs-s3
docker compose up -d
```

Verify the bind mount is correct:
```bash
docker inspect gitea --format '{{json .Mounts}}'
```

Open `http://<EC2_PUBLIC_IP>:3000`, complete the setup wizard, create a test repository, and make at least one commit.

### 7. Test Persistence

```bash
docker compose down         # stop and delete the container
docker compose up -d        # recreate from scratch
```

Open the web UI — your repository should still be present.

---

## Backup Instructions

Run the backup script to create a compressed archive of `~/data`:

```bash
./backup.sh
```

Upload the archive to S3:

```bash
ARCHIVE=$(ls -t /tmp/gitea-backup-*.tar.gz | head -n 1)
aws s3 cp "${ARCHIVE}" s3://persistencebackups/backups/
aws s3 ls s3://persistencebackups/backups/
```

---

## Restore Instructions

**Step 1 — Simulate data loss:**
```bash
docker compose down
sudo rm -rf ~/data/gitea
docker compose up -d
```
Open the web UI and confirm the repository is gone.

**Step 2 — Restore from S3:**
```bash
./restore.sh s3://persistencebackups/backups/gitea-backup-20260222T180328Z.tar.gz
```

The restore script:
1. Stops the Gitea container
2. Downloads the chosen archive from S3 using `aws s3 cp`
3. Clears `~/data` and extracts the archive back into it
4. Restarts the container

**Step 3 — Confirm recovery:**

Open `http://<EC2_PUBLIC_IP>:3000` — your repository should be back.

---

## File Structure

```
gitea-ebs-s3/
├── README.md
├── docker-compose.yml
├── backup.sh
├── restore.sh
└── mount/evidence/
    ├── lsblk.png
    ├── df-h.png
    ├── Gitea_Web_UI.png
    ├── aws_s3_ls_upload_2.png
    ├── aws_s3_ls_upload_1.png
    ├── Persistence (Container Lifecycle).png
    └── test-repo still exists.png
    └──restore/
        ├── restore_step_process.png
        ├── step1_repo_exists.png
        ├── step2_before restore_repo_missing.png
        └── step3_repo_after_restore_present.png
```

---

## AI Acknowledgment

I used Claude to help troubleshoot EBS mounting issues and scaffold the `restore.sh`. All commands were run and verified manually on my EC2 instance.

**References:**
- [Gitea Docker documentation](https://docs.gitea.com/installation/install-with-docker)
- [AWS EBS documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html)
- [AWS CLI S3 reference](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [Docker bind mounts](https://docs.docker.com/storage/bind-mounts/)