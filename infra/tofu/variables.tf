variable "libvirt_uri" {
  description = "Libvirt daemon connection URI targeting the sandbox hypervisor VM"
  type        = string
  default     = "qemu+tcp://127.0.0.1:16509/system"
}

variable "storage_pool" {
  description = "Libvirt storage pool for disk images and volumes"
  type        = string
  default     = "default"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for cloud-init injection"
  type        = string
  default     = "~/.ssh/id_sandbox_hypervisor_ed25519.pub"
}

variable "base_image_source" {
  description = "Base cloud image source URL or local path"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}
