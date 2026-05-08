variable "domain_name" {
  description = "Domain name for Route 53 hosted zone"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "wait_for_certificate_validation" {
  description = "Whether to wait for ACM certificate validation (set false if nameservers not yet configured)"
  type        = bool
  default     = false
}
