
---

## Architecture Summary

This deployment runs Gitea—a self-hosted Git service—inside a Docker container on a single AWS EC2 instance (Ubuntu). Gitea's application data is stored on a dedicated EBS volume mounted at `~/data` on the host, which is bind-mounted into the container at `/data`. This cleanly separates compute (EC2/Docker) from state (EBS), meaning the container can be recreated, updated, or replaced without any data loss. A lightweight backup workflow uses the AWS CLI to compress the EBS-backed data directory into a `.tar.gz` archive and push it to an S3 bucket, providing a durable, offsite recovery point independent of both the EC2 instance and the EBS volume.

---
