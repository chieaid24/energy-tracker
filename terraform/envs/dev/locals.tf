locals {
  name_prefix = "${var.project}-${var.env}"

  common_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.tags
  )

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}
