output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = module.oke.cluster_id
}

output "cluster_endpoints" {
  description = "OKE cluster endpoints; the API endpoint is private."
  value       = module.oke.cluster_endpoints
}

output "worker_pool_ids" {
  description = "OCIDs of the managed worker pools."
  value       = module.oke.worker_pool_ids
}