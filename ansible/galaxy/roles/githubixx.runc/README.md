<!--
Copyright (C) 2021-2025 Robert Wimmer
SPDX-License-Identifier: GPL-3.0-or-later
-->

# ansible-role-runc

Ansible role to install [runc](https://github.com/opencontainers/runc). `runc` is a CLI tool for spawning and [running](https://github.com/opencontainers/runc#using-runc) containers on Linux according to the OCI specification.

## Changelog

**Change history:**

See full [CHANGELOG](https://github.com/githubixx/ansible-role-runc/blob/master/CHANGELOG.md)

**Recent changes:**

## 0.7.1+1.3.2

- **UPDATE**
  - update runc to `1.3.2`

## 0.7.0+1.3.0

- **UPDATE**
  - update runc to `1.3.0`

- **MOLECULE**
  - Use `generic/arch` Vagrant box instead of `archlinux/archlinux` (no longer available)
  - Install `openssl` package for Archlinux
  - Removed Ubuntu 20.04 because reached end of life
  - Removed 'Upgrade the whole system' task

## 0.6.0+1.2.4

- **UPDATE**
  - update runc to `1.2.4`

## 0.5.5+1.1.14

- **UPDATE**
  - update `CHANGELOG.md`

## Installation

- Directly download from Github (Change into Ansible roles directory before cloning. You can figure out the role path by using `ansible-config dump | grep DEFAULT_ROLES_PATH` command):
`git clone https://github.com/githubixx/ansible-role-runc.git githubixx.runc`

- Via `ansible-galaxy` command and download directly from Ansible Galaxy:
`ansible-galaxy install role githubixx.runc`

- Create a `requirements.yml` file with the following content (this will download the role from Github) and install with
`ansible-galaxy role install -r requirements.yml` (change `version` if needed):

```yaml
---
roles:
  - name: githubixx.runc
    src: https://github.com/githubixx/ansible-role-runc.git
    version: 0.7.1+1.3.2
```

## Role Variables

```yaml
# runc version to install
runc_version: "1.3.2"

# Where to install "runc" binaries.
runc_bin_directory: "/usr/local/sbin"

# Owner/group of "runc" binary. If the variables are not set
# the resulting binary will be owned by the current user.
runc_owner: "root"
runc_group: "root"

# Specifies the permissions of the "runc" binary
runc_binary_mode: "0755"

# Processor architecture "runc" should run on.
# Currently only "amd64" is available.
runc_arch: "amd64"

# Name of the binary filename to download
runc_archive: "runc.{{ runc_arch }}"

# The runc download URL (normally no need to change it)
runc_url: "https://github.com/opencontainers/runc/releases/download/v{{ runc_version }}/{{ runc_archive }}"

# SHA256 checksum (normally no need to change it / see: https://github.com/opencontainers/runc/releases)
runc_checksum: "sha256:https://github.com/opencontainers/runc/releases/download/v{{ runc_version }}/runc.sha256sum"
```

## Example Playbook

```yaml
- hosts: runc
  roles:
    - githubixx.runc
```

## Testing

This role has a small test setup that is created using [Molecule](https://github.com/ansible-community/molecule), libvirt (vagrant-libvirt) and QEMU/KVM. Please see my blog post [Testing Ansible roles with Molecule, libvirt (vagrant-libvirt) and QEMU/KVM](https://www.tauceti.blog/posts/testing-ansible-roles-with-molecule-libvirt-vagrant-qemu-kvm/) how to setup. The test configuration is [here](https://github.com/githubixx/ansible-role-runc/tree/master/molecule/default).

Afterwards molecule can be executed:

```bash
molecule converge
```

This will setup a few virtual machines (VM) with different supported Linux operating systems and installs `runc`. A small verification step is also included:

```bash
molecule verify
```

To clean up run

```bash
molecule destroy
```

## License

GNU GENERAL PUBLIC LICENSE Version 3

## Author Information

[http://www.tauceti.blog](http://www.tauceti.blog)
