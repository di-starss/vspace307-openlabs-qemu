/**

  // macbook
  brew install cdrtools

  // linux
  apt install libguestfs-tools

  // img
  virt-customize -a /var/www/html/focal-server-cloudimg-amd64.img --root-password password:zalupa123123

  qemu-img create -f qcow2 -o preallocation=metadata focal-server-cloudimg-amd64-100.img 100G
  virt-resize --expand /dev/sda1 focal-server-cloudimg-amd64.img focal-server-cloudimg-amd64-100.img
  qemu-img convert -p focal-server-cloudimg-amd64-100.img -O qcow2 -c focal-server-cloudimg-amd64-100-zip.img

  virt-rescue focal-server-cloudimg-amd64-100-zip.img
  -----
  $ mkdir /mnt
  $ mount /dev/sda3 /mnt
  $ mount --bind /dev /mnt/dev
  $ mount --bind /proc /mnt/proc
  $ mount --bind /sys /mnt/sys
  $ chroot /mnt
  $ grub-install /dev/sda
  -----

**/

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.11"
    }
  }
}


//
// VARIABLES
//
variable "mgmt_user" {}
variable "mgmt_public_key" {}
variable "mgmt_private_key" {}

variable "env" {}
variable "site" {}
variable "project" {}
variable "service" {}

variable "img_name" {}

variable "vm_name" {}
variable "vm_fqdn" {}
variable "vm_hostname" {}
variable "vm_ip" {}

variable "vm_subnet" {}
variable "vm_vcpu" {}
variable "vm_ram" {}
variable "vm_if" {}
variable "vm_vdb_size_gb" {}
variable "dns_ns1" {}

variable "volume_path_img" {}
variable "volume_path_pool" {}

variable "openlabs_consul_host" {}
variable "openlabs_consul_port" {}
variable "openlabs_consul_schema" {}

variable "ansible_playbook" {}


//
// QEMU
//
resource "libvirt_pool" "pool" {
  name = "${var.project}-${var.env}-${var.service}-${var.vm_name}"
  type = "dir"
  path = "${var.volume_path_pool}/${var.env}/${var.service}/${var.vm_name}"
}

resource "libvirt_volume" "vda" {
  name = "${var.vm_fqdn}-vda.qcow2"
  pool = libvirt_pool.pool.name
  base_volume_id = "${var.volume_path_img}/${var.env}/${var.env}-${var.img_name}.qcow2"
}

resource "libvirt_volume" "vdb" {
  name = "${var.vm_fqdn}-vdb.qcow2"
  pool = libvirt_pool.pool.name
  size = 1024*1024*1024*var.vm_vdb_size_gb
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud-init/user_data.cfg")
  vars = {
    Hostname = var.vm_hostname
    MGMT_User = var.mgmt_user
    MGMT_SSHKey = var.mgmt_public_key
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/cloud-init/network_config.cfg")
  vars = {
    IPv4Address = var.vm_ip
    IPv4GW = cidrhost(var.vm_subnet, 1)
    DNS = var.dns_ns1
  }
}

// extra-vars
data "template_file" "ansible_vars" {
  template = file("${path.module}/ansible/vars.json")
  vars = {
    openlabs_consul_host = var.openlabs_consul_host
    openlabs_consul_port = var.openlabs_consul_port
    openlabs_consul_scheme = var.openlabs_consul_schema
    openlabs_env = var.env
    openlabs_vm_name = var.vm_name
    openlabs_vm_hostname = var.vm_hostname
    openlabs_mgmt_user = var.mgmt_user
    openlabs_mgmt_public_key = var.mgmt_public_key
  }
}

resource "libvirt_cloudinit_disk" "iso" {
  name = "${var.vm_fqdn}-cloud-init.iso"
  user_data = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool = libvirt_pool.pool.name
}

resource "libvirt_domain" "vm" {
  name = var.vm_fqdn
  memory = 1024*var.vm_ram
  vcpu = var.vm_vcpu
  autostart = true
  cloudinit = libvirt_cloudinit_disk.iso.id

  cpu {
    mode = "host-passthrough"
  }

  xml {
    xslt = templatefile("${path.module}/xslt/ovs.xsl", var.vm_if)
  }

  disk {
    volume_id = libvirt_volume.vda.id
  }

  disk {
    volume_id = libvirt_volume.vdb.id
  }

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }

  // ansible-core
  provisioner "file" {
    source      = "${path.module}/ansible/core.yaml"
    destination = "/tmp/core.yaml"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-core-kvm
  provisioner "file" {
    source      = "${path.module}/ansible/core_compute.yaml"
    destination = "/tmp/core_compute.yaml"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-core-storage
  provisioner "file" {
    source      = "${path.module}/ansible/core_storage.yaml"
    destination = "/tmp/core_storage.yaml"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-core-network
  provisioner "file" {
    source      = "${path.module}/ansible/core_network.yaml"
    destination = "/tmp/core_network.yaml"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-vars
  provisioner "file" {
    content      = data.template_file.ansible_vars.rendered
    destination = "/tmp/vars.json"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-tmpl
  provisioner "file" {
    source      = "${path.module}/ansible/tmpl"
    destination = "/tmp/tmpl"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  // ansible-playbook
  provisioner "file" {
    source      = "${path.module}/ansible/${var.ansible_playbook}"
    destination = "/tmp/${var.ansible_playbook}"

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt upgrade -y",
      "sudo apt install ansible -y",
      "sudo ansible-playbook /tmp/${var.ansible_playbook}"
    ]

    connection {
      type     = "ssh"
      user     = var.mgmt_user
      private_key = var.mgmt_private_key
      host = var.vm_ip
    }
  }

}