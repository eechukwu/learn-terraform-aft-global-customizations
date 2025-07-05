# ==========================================
# locals.tf (KEEP AS IS)
# ==========================================
locals {
  # canonical list – add/remove regions here **once**
  target_regions = [
    "us-east-1",
    "eu-west-2",
    "ap-southeast-1",
    "us-west-2",
    "ca-central-1"
  ]

  # same list, but with hyphens replaced so it matches alias names
  target_regions_clean = [
    for r in local.target_regions : replace(r, "-", "_")
  ]

  # map region -> provider reference (aws.<alias>)
  region_providers = {
    for r in local.target_regions :
    r => "aws.${replace(r, "-", "_")}"
  }
}