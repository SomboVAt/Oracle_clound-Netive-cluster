provider "oci" {
  config_file_profile = var.oci_profile_name
  region              = var.region
}

provider "oci" {
  alias               = "home"
  config_file_profile = var.oci_profile_name
  region              = var.home_region == "" ? var.region : var.home_region
}