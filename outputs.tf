output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.web-server-instance.public_ip
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.main.address
}

output "web_url" {
  description = "URL to access the web server"
  value       = "http://${aws_instance.web-server-instance.public_ip}/index.php"
}