output "bucket_name" {
  description = "Console asset bucket name."
  value       = aws_s3_bucket.console.id
}

output "console_url" {
  description = "Console URL."
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.this.id
}
