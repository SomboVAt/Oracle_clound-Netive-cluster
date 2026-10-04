variable "deploy_oke" {
  description = "Set to false to skip OCI provisioning and validate the Terraform configuration in a local or CI environment without Oracle credentials."
  type        = bool
  default     = true
}

variable "oci_profile_name" {
  description = "Profile name from the local OCI CLI configuration file."
  type        = string
  default     = "DEFAULT"
}

variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
  default     = ""

  validation {
    condition     = var.deploy_oke == false || trimspace(var.tenancy_ocid) != ""
    error_message = "Set tenancy_ocid when deploy_oke is true."
  }
}

variable "compartment_ocid" {
  description = "Compartment OCID in which the OKE cluster and node pool are managed."
  type        = string
  default     = ""

  validation {
    condition     = var.deploy_oke == false || trimspace(var.compartment_ocid) != ""
    error_message = "Set compartment_ocid when deploy_oke is true."
  }
}

variable "region" {
  description = "OCI region identifier for the cluster."
  type        = string
  default     = ""

  validation {
    condition     = var.deploy_oke == false || trimspace(var.region) != ""
    error_message = "Set region when deploy_oke is true."
  }
}

variable "home_region" {
  description = "Tenancy home region; leave empty to use region."
  type        = string
  default     = ""
}

variable "vcn_ocid" {
  description = "OCID of the pre-existing, security-approved VCN."
  type        = string
  default     = ""

  validation {
    condition     = var.deploy_oke == false || trimspace(var.vcn_ocid) != ""
    error_message = "Set vcn_ocid when deploy_oke is true."
  }
}

variable "subnets" {
  description = "Existing private OKE endpoint, worker, and internal load-balancer subnets."
  type = map(object({
    id = string
  }))
  default = {}

  validation {
    condition = var.deploy_oke == false || (
      alltrue([
        for required_subnet in ["cp", "workers", "int_lb"] : contains(keys(var.subnets), required_subnet)
      ]) && length(keys(var.subnets)) == 3
    )
    error_message = "subnets must define cp, workers, and int_lb entries with existing private subnet OCIDs when deploy_oke is true."
  }
}

variable "control_plane_allowed_cidrs" {
  description = "Trusted administrator/VPN CIDRs allowed to reach the private Kubernetes API endpoint."
  type        = list(string)
  default     = []

  validation {
    condition     = var.deploy_oke == false || length(var.control_plane_allowed_cidrs) > 0
    error_message = "Set at least one narrowly scoped administrator or VPN CIDR when deploy_oke is true."
  }
}

variable "cluster_name" {
  description = "Name for the OKE cluster."
  type        = string
  default     = "core-banking-oke"
}

variable "kubernetes_version" {
  description = "OKE-supported Kubernetes version available in the selected region."
  type        = string
  default     = "v1.36.4"

  validation {
    condition     = var.deploy_oke == false || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Use a full Kubernetes version such as v1.36.4, after confirming OKE offers it in the selected region."
  }
}

variable "worker_count" {
  description = "Initial number of managed application worker nodes; benchmark before production approval."
  type        = number
  default     = 3

  validation {
    condition     = var.deploy_oke == false || (var.worker_count >= 3 && floor(var.worker_count) == var.worker_count)
    error_message = "Use at least three whole worker nodes for this starting HA profile."
  }
}

variable "worker_placement_ads" {
  description = "Availability-domain numbers available in the selected region; use fault domains for single-AD regions as appropriate."
  type        = list(number)
  default     = []

  validation {
    condition     = var.deploy_oke == false || (length(var.worker_placement_ads) > 0 && length(distinct(var.worker_placement_ads)) == length(var.worker_placement_ads))
    error_message = "Provide one or more distinct availability-domain numbers valid for the selected region when deploy_oke is true."
  }
}

variable "worker_shape" {
  description = "x86 OCI shape for OKE worker nodes."
  type        = string
  default     = "VM.Standard.E6.Flex"
}

variable "worker_ocpus" {
  description = "OCPUs per worker node; validate by representative performance testing."
  type        = number
  default     = 8
}

variable "worker_memory_gb" {
  description = "Memory in GB per worker node; validate by representative performance testing."
  type        = number
  default     = 64
}

variable "worker_boot_volume_gb" {
  description = "Boot volume size in GB per worker node."
  type        = number
  default     = 150
}

variable "worker_os_version" {
  description = "Oracle Linux version for an OKE-supported node image; confirm vendor certification before changing."
  type        = string
  default     = "8"
}

variable "cluster_kms_key_ocid" {
  description = "Optional customer-managed KMS key OCID for Kubernetes secret encryption."
  type        = string
  default     = ""
}

variable "worker_volume_kms_key_ocid" {
  description = "Optional customer-managed KMS key OCID for worker boot volumes."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment tag applied to created OKE resources."
  type        = string
  default     = "production"
}