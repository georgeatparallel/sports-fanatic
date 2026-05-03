output "zone_id" {
  description = "Route 53 zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "nameservers" {
  description = "Route 53 nameservers (update your domain registrar with these)"
  value       = aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.main.arn
}
