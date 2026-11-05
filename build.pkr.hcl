variable "username" {
  type    = string
  default = "nathan"
}

variable "build_key" {
  type    = string
  default = "/tmp/packer-build-key"
}

variable "cpus" {
  type = string
  default = "4"
}

source "qemu" "base" {
  iso_url              = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  iso_checksum         = "file:https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS"
  disk_image           = true
  format               = "qcow2"
  output_directory     = "out"
  headless             = true
  ssh_username         = "debian"
  ssh_private_key_file = var.build_key
  shutdown_command     = "sudo shutdown -P now"
  cd_files = ["seed/user-data", "seed/meta-data"]
  cd_label = "cidata"
  vm_name = "server-image.qcow2"
  cpus = var.cpus
}

locals {
  packages = [
    "zsh",
    "zsh-autosuggestions",
    "htop",
    "btop",
    "hx",
    "vis",
    "cron",
    "bat",
    "cockpit",
    "podman",
    "cockpit-podman",
    "cockpit-storaged",
    "git",
    "g++",
  ]
}

build {
  sources = ["source.qemu.base"]

  provisioner "file" {
    source      = "files/zshrc"
    destination = "/tmp/zshrc"
  }

  provisioner "file" {
    source      = "files/zprofile"
    destination = "/tmp/zprofile"
  }

  provisioner "shell" {
    inline = ["mkdir -p /tmp/helix"]
  }

  provisioner "file" {
    source      = "files/helix/"
    destination = "/tmp/helix"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "INIT_USER=${var.username}",
    ]
    execute_command = "{{ .Vars }} sudo -E bash '{{ .Path }}'"
    inline = [
      "set -eux",

      # update and upgrade
      "apt-get update",
      "apt-get -y upgrade",

      # new packages
      "apt-get install -y ${join("  ", local.packages)}",

      # user, with zsh as login shell
      "id -u \"$INIT_USER\" >/dev/null 2>&1 || useradd -m -s /usr/bin/zsh \"$INIT_USER\"",

      # dotfiles
      "install -m 644 -o \"$INIT_USER\" -g \"$INIT_USER\" /tmp/zshrc /home/$INIT_USER/.zshrc",
      "install -m 644 -o \"$INIT_USER\" -g \"$INIT_USER\" /tmp/zprofile /home/$INIT_USER/.zprofile",

      # helix config
      "install -d -o \"$INIT_USER\" -g \"$INIT_USER\" /home/$INIT_USER/.config/helix",
      "cp -r /tmp/helix/. /home/$INIT_USER/.config/helix/",
      "chown -R \"$INIT_USER:$INIT_USER\" /home/$INIT_USER/.config",

      # helix grammars
      "sudo -u \"$INIT_USER\" -H env GIT_TERMINAL_PROMPT=0 hx --grammar fetch || true",
      "sudo -u \"$INIT_USER\" -H hx --grammar build || true",

      # enable services
      "systemctl enable cron.service cockpit.socket podman.socket",

      # enable user services
      # needs dbus?
      # "sudo -u \"$INIT_USER\" -H systemctl enable --user podman-restart.service",

      # passwordless sudo for default user
      "echo \"$INIT_USER ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/90-$INIT_USER",
      "chmod 440 /etc/sudoers.d/90-$INIT_USER",
      "visudo -c -f /etc/sudoers.d/90-$INIT_USER",
    ]
  }
}
