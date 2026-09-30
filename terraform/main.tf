module "oke" {
  source = "git::https://github.com/oracle-terraform-modules/terraform-oci-oke.git?ref=v5.5.1"

  providers = {
    oci      = oci
    oci.home = oci.home
  }

  tenancy_id          = var.tenancy_ocid
  config_file_profile = var.oci_profile_name
  compartment_id      = var.compartment_ocid
  region              = var.region
  home_region         = var.home_region == "" ? var.region : var.home_region

  create_vcn = false
  vcn_id     = var.vcn_ocid
  subnets    = var.subnets

  create_cluster                    = true
  cluster_name                      = var.cluster_name
  cluster_type                      = "enhanced"
  kubernetes_version                = var.kubernetes_version
  control_plane_is_public           = false
  assign_public_ip_to_control_plane = false
  control_plane_allowed_cidrs       = var.control_plane_allowed_cidrs
  cluster_kms_key_id                = var.cluster_kms_key_ocid
  load_balancers                    = "internal"
  preferred_load_balancer           = "internal"

  create_bastion  = false
  create_operator = false

  create_iam_resources = false
  output_detail        = false
  await_node_readiness = "all"

  worker_pool_mode                      = "node-pool"
  worker_pool_size                      = var.worker_count
  worker_is_public                      = false
  worker_image_type                     = "oke"
  worker_image_os                       = "Oracle Linux"
  worker_image_os_version               = var.worker_os_version
  worker_legacy_imds_endpoints_disabled = true
  worker_volume_kms_key_id              = var.worker_volume_kms_key_ocid
  allow_worker_internet_access          = false
  allow_pod_internet_access             = false

  worker_pools = {
    core_banking_app = {
      mode             = "node-pool"
      size             = var.worker_count
      shape            = var.worker_shape
      ocpus            = var.worker_ocpus
      memory           = var.worker_memory_gb
      boot_volume_size = var.worker_boot_volume_gb
      image_type       = "oke"
      os               = "Oracle Linux"
      os_version       = var.worker_os_version
      assign_public_ip = false
      placement_ads    = var.worker_placement_ads
    }
  }

  freeform_tags = {
    application = "core-banking"
    environment = var.environment
    managed_by  = "terraform"
  }
}