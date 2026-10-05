# ==============================================================================
# TACTICAL MULTI-BEARER NETWORKS (Simulated Radio Links)
# ==============================================================================

# 1. Bearer: P-LEO Satellite (Starlink / Sailor Edge / SDA Tranche)
# Low latency (~40ms), High bandwidth (100Mbps+)
resource "libvirt_network" "br_pleops" {
  name      = "br-pleops"
  mode      = "none"
  autostart = true
}

# 2. Bearer: MILSATCOM (WGS / Inmarsat / Wideband Global SATCOM)
# High latency (~500ms GEO), Moderate bandwidth
resource "libvirt_network" "br_milsat" {
  name      = "br-milsat"
  mode      = "none"
  autostart = true
}

# 3. Bearer: Tactical Line-of-Sight RF (Link-16 / CDL / Tactical UHF/VHF)
# Variable latency (~100ms), Low bandwidth (1-5Mbps)
resource "libvirt_network" "br_losrf" {
  name      = "br-losrf"
  mode      = "none"
  autostart = true
}

# ==============================================================================
# SHIPBOARD SECURITY ENCLAVES
# ==============================================================================

# Unclassified Shipboard Enclave (NIPR / UNCLASS LAN)
resource "libvirt_network" "br_enclave_unclass" {
  name      = "br-enclave-unclass"
  mode      = "none"
  autostart = true
}

# Classified / Mission Critical Enclave (SIPR / SECRET LAN)
resource "libvirt_network" "br_enclave_secret" {
  name      = "br-enclave-secret"
  mode      = "none"
  autostart = true
}

# ==============================================================================
# SHORE HUB / CLOUD OPERATIONS NETWORK
# ==============================================================================

# Simulated Tactical Shore / HQ Backbone
resource "libvirt_network" "br_shore_hub" {
  name      = "br-shore-hub"
  mode      = "nat"
  autostart = true
  addresses = ["10.200.1.0/24"]
  dhcp {
    enabled = true
  }
}
