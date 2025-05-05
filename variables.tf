variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1" # Example: Frankfurt
}

variable "instance_type" {
  description = "EC2 instance type for the RustDesk server"
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair in the selected region for SSH access"
  type        = string
  # No default - user MUST provide this in terraform.tfvars
  # Example: key_pair_name = "rustdesk-frankfurt-key"
}

variable "deploy_pro_version" {
  description = "Set to true to deploy RustDesk Pro, false for OSS version"
  type        = bool
  default     = false
}

variable "rustdesk_pro_license_secret_name" {
  description = "Name of the secret in AWS Secrets Manager containing the RustDesk Pro license key string. Required only if deploy_pro_version is true."
  type        = string
  default     = "" # Leave blank if deploying OSS
  # Example: rustdesk_pro_license_secret_name = "rustdesk/pro-license"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access. Use x.x.x.x/32 for a single IP."
  type        = list(string) # Changed to list for potentially multiple IPs/ranges
  default     = ["0.0.0.0/0"] # Allow from anywhere by default (less secure)
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Specific Availability Zone to deploy the subnet and instance into (e.g., eu-central-1a). Leave null to let AWS choose."
  type        = string
  default     = null # Let AWS choose an AZ in the region by default
}

variable "server_name_tag" {
  description = "Value for the Name tag applied to resources"
  type        = string
  default     = "RustDesk-Server"
} 