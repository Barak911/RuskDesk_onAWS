# RustDesk Server on AWS using Terraform

This project uses Terraform to deploy a self-hosted RustDesk server (either Open Source or Pro version) on an AWS EC2 instance within a dedicated VPC.

## Architecture

*   **Compute:** A single AWS EC2 instance (default `t3.small`) running Ubuntu 22.04 LTS.
*   **Networking:** Creates a new VPC, public subnet, Internet Gateway, Route Table, and Security Group.
    *   The Security Group allows required RustDesk ports (TCP 21115-21117, 21119, UDP 21116) and SSH (TCP 22).
*   **Deployment:** Docker and Docker Compose v1 are installed on the instance via a `user_data` script (cloud-init).
*   **RustDesk Service:** The `user_data` script dynamically creates a `docker-compose.yml` file and starts the appropriate RustDesk container(s):
    *   **OSS:** Runs `hbbs` and `hbbr` services using the `rustdesk/rustdesk-server` image.
    *   **Pro:** Runs a single service using the `rustdesk/rustdesk-server-pro` image.
*   **Secrets (Pro Only):** If deploying the Pro version, the instance requires an IAM role granting permission to fetch the license key from AWS Secrets Manager.

## Prerequisites

1.  **AWS Account:** An active AWS account.
2.  **Terraform:** Terraform CLI installed locally (~> 1.0).
3.  **AWS Credentials:** Configure AWS credentials locally for Terraform (e.g., via environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, or an AWS profile).
4.  **EC2 Key Pair:** An EC2 Key Pair must exist in the target AWS region. You will need its name and the corresponding private key file (`.pem`) for SSH access.
5.  **RustDesk Pro License (Optional):** If deploying the Pro version:
    *   A valid RustDesk Pro license key.
    *   The license key string must be stored as a secret in AWS Secrets Manager in the target region.

## Configuration

1.  **Navigate to Terraform Directory:**
    ```bash
    cd terraform
    ```
2.  **Create `terraform.tfvars`:** Copy the example file and customize it:
    ```bash
    cp terraform.tfvars.example terraform.tfvars
    nano terraform.tfvars
    ```
3.  **Edit `terraform.tfvars`:**
    *   **REQUIRED:** Set `key_pair_name` to the exact name of your existing EC2 Key Pair.
    *   **RECOMMENDED:**
        *   Set `aws_region` if different from the default (`eu-central-1`).
        *   Set `ssh_allowed_cidr` to your IP address (e.g., `["YOUR_IP/32"]`) for better security.
    *   **PRO DEPLOYMENT:**
        *   Set `deploy_pro_version = true`.
        *   Set `rustdesk_pro_license_secret_name` to the exact name of the secret you created in AWS Secrets Manager containing your license key.
    *   **OPTIONAL:** Adjust `instance_type`, `vpc_cidr`, `subnet_cidr`, `availability_zone`, `server_name_tag` as needed.

## Deployment

1.  **Navigate:** Ensure you are in the `terraform/` directory.
2.  **Initialize:** Download Terraform providers.
    ```bash
    terraform init
    ```
3.  **Plan (Optional):** Review the resources Terraform will create.
    ```bash
    terraform plan
    ```
4.  **Apply:** Create the AWS resources.
    ```bash
    terraform apply
    ```
    Type `yes` when prompted to confirm.

Terraform will output the `instance_public_ip` upon successful completion.

## Connecting with RustDesk Client

1.  **Get Server IP:** Note the `instance_public_ip` from the `terraform apply` output or find it in the AWS EC2 Console.
2.  **Open RustDesk Client:** Go to Settings -> Network (or ID/Relay server).
3.  **Configure:**
    *   **ID Server:** Enter the server's Public IP address.
    *   **Relay Server:** Enter the server's Public IP address.
    *   **API Server:** Leave blank.
    *   **Key:**
        *   **OSS Version:** Leave blank.
        *   **Pro Version:** Enter your RustDesk Pro license key string (the same one stored in Secrets Manager).
4.  **Connect:** Click OK. The client should show "Ready".

## Accessing the Server via SSH

You can connect to the instance using the private key file corresponding to the `key_pair_name` you specified and the `ubuntu` user.

```bash
ssh -i /path/to/your/private_key.pem ubuntu@<instance_public_ip>
```

Remember to set correct permissions on your private key file: `chmod 400 /path/to/your/private_key.pem`.

## Destroying Infrastructure

To remove all AWS resources created by this configuration:

1.  **Navigate:** Ensure you are in the `terraform/` directory.
2.  **Destroy:**
    ```bash
    terraform destroy
    ```
    Type `yes` when prompted to confirm. 