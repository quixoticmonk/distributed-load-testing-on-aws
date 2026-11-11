provider "aws" {
  region = var.hub_region

  default_tags {
    tags = local.default_tags
  }
}

# One provider per spoke region. Add more aliases (and module blocks) for more regions.
provider "aws" {
  alias  = "spoke"
  region = var.spoke_region

  default_tags {
    tags = local.default_tags
  }
}
