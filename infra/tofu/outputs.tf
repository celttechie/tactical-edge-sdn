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

output "ssh_config" {
  description = "OpenSSH client configuration block for the ephemeral lab VMs"
  value       = <<-EOT
    # Tactical Edge SDN - Ephemeral Nested Lab VMs
    Host legacy-router 10.200.1.2
        HostName 10.200.1.2
        User ${var.admin_username}
        ProxyJump ${var.hypervisor_ssh_host}
        IdentityFile ${var.ssh_private_key_path}
        StrictHostKeyChecking accept-new

    Host shore-gateway 10.200.1.10
        HostName 10.200.1.10
        User ${var.admin_username}
        ProxyJump ${var.hypervisor_ssh_host}
        IdentityFile ${var.ssh_private_key_path}
        StrictHostKeyChecking accept-new

    Host enclave-client 10.10.1.10
        HostName 10.10.1.10
        User ${var.admin_username}
        ProxyJump legacy-router
        IdentityFile ${var.ssh_private_key_path}
        StrictHostKeyChecking accept-new
  EOT
}
