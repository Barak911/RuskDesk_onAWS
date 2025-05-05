output "instance_public_ip" {
  description = "Public IP address of the RustDesk EC2 instance."
  value       = aws_instance.rustdesk_server.public_ip
}

output "instance_id" {
  description = "ID of the RustDesk EC2 instance."
  value       = aws_instance.rustdesk_server.id
} 