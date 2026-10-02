output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = try(module.oke[0].cluster_id, null)
}

output "cluster_endpoints" {
  description = "OKE cluster endpoints; the API endpoint is private."
  value       = try(module.oke[0].cluster_endpoints, null)
}

output "worker_pool_ids" {
  description = "OCIDs of the managed worker pools."
  value       = try(module.oke[0].worker_pool_ids, null)
}

output "deploy_oke" {
  description = "Whether the OCI OKE module was enabled for this run."
  value       = var.deploy_oke
}