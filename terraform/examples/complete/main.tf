locals {
  artifacts_dir = abspath("${path.root}/../../build")

  default_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.name
  }
}

module "hub" {
  source = "../../modules/dlt-hub"

  name              = var.name
  admin_email       = var.admin_email
  admin_name        = var.admin_name
  artifacts_dir     = local.artifacts_dir
  deploy_mcp_server = var.deploy_mcp_server
  egress_cidr_block = var.egress_cidr_block
}

module "region_spoke" {
  source = "../../modules/dlt-region"

  providers = {
    aws     = aws.spoke
    aws.hub = aws
  }

  name                         = var.name
  egress_cidr_block            = var.egress_cidr_block
  hub                          = module.hub.regional_inputs
  real_time_data_publisher_zip = "${local.artifacts_dir}/lambda/real-time-data-publisher.zip"
}
