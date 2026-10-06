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
# CLOUD-INIT DISKS
# ==============================================================================

resource "libvirt_cloudinit_disk" "cloudinit_router" {
  name = "legacy-router-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_router.cfg", {
    hostname       = "legacy-router"
    admin_username = var.admin_username
    ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  })
  network_config = templatefile("${path.module}/templates/network_config_router.cfg", {})
}

resource "libvirt_cloudinit_disk" "cloudinit_shore" {
  name = "shore-gateway-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_shore.cfg", {
    hostname       = "shore-gateway"
    admin_username = var.admin_username
    ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  })
  network_config = templatefile("${path.module}/templates/network_config_shore.cfg", {})
}

resource "libvirt_cloudinit_disk" "cloudinit_enclave" {
  name = "enclave-client-cloudinit.iso"
  pool = var.storage_pool
  user_data = templatefile("${path.module}/templates/cloud_init_enclave.cfg", {
    hostname       = "enclave-client"
    admin_username = var.admin_username
    ssh_public_key = file(pathexpand(var.ssh_public_key_path))
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
