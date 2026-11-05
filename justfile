set shell := ["bash", "-c"]

build_key := "/tmp/packer-build-key"

clean:
    rm -rf out
    rm -f {{ build_key }} {{ build_key }}.pub seed/user-data

build:
    #!/usr/bin/env bash
    set -euo pipefail

    # clean up temporary build ssh key pair on exit
    trap 'rm -f {{ build_key }} {{ build_key }}.pub seed/user-data' EXIT

    # remove any stale build key pair
    rm -f {{ build_key }} {{ build_key }}.pub

    ssh-keygen -q -t ed25519 -N '' -f {{ build_key }}
    printf '#cloud-config\nssh_authorized_keys:\n  - %s\n' "$(cat {{ build_key }}.pub)" > seed/user-data

    packer validate -var 'build_key={{ build_key }}' .
    packer build -force -var 'build_key={{ build_key }}' .

run user="nathan" pubkey="~/.ssh/id_ed25519.pub" cpus="4" mem="4G":
    #!/usr/bin/env bash
    set -euo pipefail

    seed=$(mktemp -d)

    # remove temporary seed on exit
    trap 'rm -rf "$seed"' EXIT

    # seed data and iso
    printf 'instance-id: run-%s\nlocal-hostname: image-test\n' "$(date +%s)" > "$seed/meta-data"
    printf '#cloud-config\nusers:\n  - default\n  - name: %s\n    ssh_authorized_keys:\n      - %s\n' "{{ user }}" "$(cat {{ pubkey }})" > "$seed/user-data"
    mkisofs -quiet -output "$seed/seed.iso" -volid cidata -joliet -rock "$seed/user-data" "$seed/meta-data"

    echo "Once booted: ssh -p 2222 -o UserKnownHostsFile=/dev/null {{ user }}@localhost"
    echo "Exit the VM console with Ctrl-a then x"

    echo "Booting in 5 seconds..."
    sleep 5

    qemu-system-x86_64 \
        -machine type=pc,accel=kvm -cpu host -smp {{ cpus }} -m {{ mem }} \
        -drive file=out/server-image.qcow2,if=virtio,format=qcow2 -snapshot \
        -cdrom "$seed/seed.iso" \
        -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22,hostfwd=tcp::9090-:9090 \
        -nographic

connect user="nathan":
    ssh -p 2222 -o UserKnownHostsFile=/dev/null "{{ user }}@localhost"
