# ==============================================================================
# DISK VOLUMES
# ==============================================================================

resource "libvirt_volume" "legacy_router_disk" {
  name           = "legacy-router-disk.qcow2"
  pool           = var.storage_pool
  base_volume_name = "ubuntu-22.04-base.qcow2"
  format         = "qcow2"
  size           = 16106127360 # 15 GB
}

resource "libvirt_volume" "shore_gateway_disk" {
  name           = "shore-gateway-disk.qcow2"
  pool           = var.storage_pool
  base_volume_name = "ubuntu-22.04-base.qcow2"
  format         = "qcow2"
  size           = 16106127360 # 15 GB
}

resource "libvirt_volume" "enclave_client_disk" {
  name           = "enclave-client-disk.qcow2"
  pool           = var.storage_pool
  base_volume_name = "ubuntu-22.04-base.qcow2"
  format         = "qcow2"
  size           = 16106127360 # 15 GB
}

# ==============================================================================
# ==============================================================================
# APPLICATION CODE ARCHIVE
# ==============================================================================

data "archive_file" "app_bundle" {
  type        = "zip"
  source_dir  = "${path.module}/../../src"
  output_path = "${path.module}/app_bundle.zip"
}

# ==============================================================================
# ==============================================================================
# DETERMINISTIC SSH HOST KEYS
# ==============================================================================

resource "tls_private_key" "router_host_key" {
  algorithm = "ED25519"
}

resource "tls_private_key" "shore_host_key" {
  algorithm = "ED25519"
}

resource "tls_private_key" "enclave_host_key" {
  algorithm = "ED25519"
}

# Automatically pin and generate dedicated lab known_hosts file
resource "local_file" "tactical_known_hosts" {
  filename        = pathexpand("~/.ssh/known_hosts_tactical_lab")
  file_permission = "0600"
  content         = <<-EOT
    10.200.1.2 ${tls_private_key.router_host_key.public_key_openssh}
    ship-gateway ${tls_private_key.router_host_key.public_key_openssh}
    10.200.1.10 ${tls_private_key.shore_host_key.public_key_openssh}
    shore-gateway ${tls_private_key.shore_host_key.public_key_openssh}
    10.10.1.10 ${tls_private_key.enclave_host_key.public_key_openssh}
    enclave-client ${tls_private_key.enclave_host_key.public_key_openssh}
  EOT
}

# ==============================================================================
# CLOUD-INIT DISKS
# ==============================================================================

resource "libvirt_cloudinit_disk" "cloudinit_router" {
  name = "ship-gateway-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_router.cfg", {
    hostname          = "ship-gateway"
    admin_username    = var.admin_username
    ssh_public_key    = file(pathexpand(var.ssh_public_key_path))
    host_private_key  = tls_private_key.router_host_key.private_key_openssh
    host_public_key   = tls_private_key.router_host_key.public_key_openssh
    app_zip_b64       = data.archive_file.app_bundle.output_base64sha256 != "" ? filebase64(data.archive_file.app_bundle.output_path) : ""
  })
  network_config = templatefile("${path.module}/templates/network_config_router.cfg", {})
}

resource "libvirt_cloudinit_disk" "cloudinit_shore" {
  name = "shore-gateway-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_shore.cfg", {
    hostname          = "shore-gateway"
    admin_username    = var.admin_username
    ssh_public_key    = file(pathexpand(var.ssh_public_key_path))
    host_private_key  = tls_private_key.shore_host_key.private_key_openssh
    host_public_key   = tls_private_key.shore_host_key.public_key_openssh
    app_zip_b64       = data.archive_file.app_bundle.output_base64sha256 != "" ? filebase64(data.archive_file.app_bundle.output_path) : ""
  })
  network_config = templatefile("${path.module}/templates/network_config_shore.cfg", {})
}

resource "libvirt_cloudinit_disk" "cloudinit_enclave" {
  name = "enclave-client-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_enclave.cfg", {
    hostname          = "enclave-client"
    admin_username    = var.admin_username
    ssh_public_key    = file(pathexpand(var.ssh_public_key_path))
    host_private_key  = tls_private_key.enclave_host_key.private_key_openssh
    host_public_key   = tls_private_key.enclave_host_key.public_key_openssh
    app_zip_b64       = data.archive_file.app_bundle.output_base64sha256 != "" ? filebase64(data.archive_file.app_bundle.output_path) : ""
  })
  network_config = templatefile("${path.module}/templates/network_config_enclave.cfg", {})
}

# ==============================================================================
# VIRTUAL MACHINE DOMAINS
# ==============================================================================

# 1. Legacy Shipboard Router VM
resource "libvirt_domain" "legacy_router" {
  name   = "legacy-router"
  memory = 2048
  vcpu   = 2

  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit_router.id

  # Interface 1: UNCLASS Enclave (10.10.1.1)
  network_interface {
    network_name = libvirt_network.br_enclave_unclass.name
    mac          = "52:54:00:10:01:01"
  }

  # Interface 2: SECRET Enclave (10.10.2.1)
  network_interface {
    network_name = libvirt_network.br_enclave_secret.name
    mac          = "52:54:00:10:02:01"
  }

  # Interface 3: P-LEO Bearer (10.100.1.2)
  network_interface {
    network_name = libvirt_network.br_pleops.name
    mac          = "52:54:00:20:01:02"
  }

  # Interface 4: MILSATCOM Bearer (10.100.2.2)
  network_interface {
    network_name = libvirt_network.br_milsat.name
    mac          = "52:54:00:20:02:02"
  }

  # Interface 5: Line-of-Sight RF Bearer (10.100.3.2)
  network_interface {
    network_name = libvirt_network.br_losrf.name
    mac          = "52:54:00:20:03:02"
  }

  # Interface 6: Management / Shore Hub (10.200.1.2)
  network_interface {
    network_name = libvirt_network.br_shore_hub.name
    mac          = "52:54:00:30:01:02"
  }

  disk {
    volume_id = libvirt_volume.legacy_router_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# 2. Simulated Shore Gateway VM
resource "libvirt_domain" "shore_gateway" {
  name   = "shore-gateway"
  memory = 2048
  vcpu   = 2

  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit_shore.id

  # Interface 1: P-LEO Bearer Shore (10.100.1.1)
  network_interface {
    network_name = libvirt_network.br_pleops.name
    mac          = "52:54:00:20:01:01"
  }

  # Interface 2: MILSATCOM Bearer Shore (10.100.2.1)
  network_interface {
    network_name = libvirt_network.br_milsat.name
    mac          = "52:54:00:20:02:01"
  }

  # Interface 3: Line-of-Sight RF Bearer Shore (10.100.3.1)
  network_interface {
    network_name = libvirt_network.br_losrf.name
    mac          = "52:54:00:20:03:01"
  }

  # Interface 4: Shore Hub Backbone (10.200.1.10)
  network_interface {
    network_name = libvirt_network.br_shore_hub.name
    mac          = "52:54:00:30:01:01"
  }

  disk {
    volume_id = libvirt_volume.shore_gateway_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# 3. Enclave Test Workload VM
resource "libvirt_domain" "enclave_client" {
  name   = "enclave-client"
  memory = 2048
  vcpu   = 2

  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.cloudinit_enclave.id

  # Interface 1: UNCLASS Enclave (10.10.1.10)
  network_interface {
    network_name = libvirt_network.br_enclave_unclass.name
    mac          = "52:54:00:10:01:10"
  }

  disk {
    volume_id = libvirt_volume.enclave_client_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# ==============================================================================
# CONVERGENCE & COMPLETION BARRIER
# ==============================================================================

# Ensures OpenTofu apply blocks and does not return until all guest VMs have
# fully converged, completed cloud-init bootstrap, and are ready for testing.
resource "terraform_data" "wait_for_convergence" {
  depends_on = [
    libvirt_domain.legacy_router,
    libvirt_domain.shore_gateway,
    libvirt_domain.enclave_client,
    local_file.tactical_known_hosts
  ]

  provisioner "local-exec" {
    command = <<-EOT
      "${path.module}/../../scripts/setup-ssh.sh" --non-interactive
      echo "==> [OpenTofu Barrier] Awaiting guest OS cloud-init completion across all nodes..."
      for host in ship-gateway shore-gateway enclave-client; do
        echo " -> Awaiting $host convergence..."
        converged=false
        for attempt in $(seq 1 60); do
          if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$host" "cloud-init status --wait" >/dev/null 2>&1; then
            echo " [✓] $host cloud-init complete."
            converged=true
            break
          fi
          sleep 2
        done
        if [ "$converged" = false ]; then
          echo " [✗] Error: $host failed to converge within 120 seconds."
          exit 1
        fi
      done
      echo "==> [OpenTofu Barrier] All lab nodes 100% converged and operational."
    EOT
  }
}

