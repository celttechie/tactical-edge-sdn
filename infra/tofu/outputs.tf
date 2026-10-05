output "legacy_router_ip" {
  description = "Management / Shore hub IP of Legacy Router"
  value       = "10.200.1.2"
}

output "shore_gateway_ip" {
  description = "Shore Gateway Endpoint IP"
  value       = "10.200.1.10"
}

output "enclave_client_ip" {
  description = "Enclave Client IP"
  value       = "10.10.1.10"
}

output "networks" {
  description = "Created tactical multi-bearer and enclave networks"
  value = {
    pleops          = libvirt_network.br_pleops.name
    milsat          = libvirt_network.br_milsat.name
    losrf           = libvirt_network.br_losrf.name
    enclave_unclass = libvirt_network.br_enclave_unclass.name
    enclave_secret  = libvirt_network.br_enclave_secret.name
    shore_hub       = libvirt_network.br_shore_hub.name
  }
}
