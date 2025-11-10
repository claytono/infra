<!--
Copyright (C) 2021-2025 Robert Wimmer
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

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

### UPDATE

- update `CHANGELOG.md`

## 0.5.4+1.1.14

- **UPDATE**
  - update runc to `1.1.14`

## 0.5.3+1.1.13

- **UPDATE**
  - update runc to `1.1.13`

### OTHER

- add support for Ubuntu 24.04

## 0.5.2+1.1.12

- **UPDATE**
  - update runc to `1.1.12`

## 0.5.1+1.1.11

- **UPDATE**
  - update runc to `1.1.11`

### OTHER CHANGES

- adjust Github action because of Ansible Galaxy changes

### MOLECULE

- Change IP addresses

## 0.5.0+1.1.10

### BREAKING

- change default value of `runc_bin_directory` from `/usr/local/bin` to `/usr/local/sbin`

## 0.4.1+1.1.10

- update runc to `1.1.10`

## 0.4.0+1.1.9

- add Github actions workflow

## 0.3.0+1.1.9

- update runc to `1.1.9`
- Molecule: rename scenario from `kvm` to `default`
- remove support for Ubuntu 18.04 (reached EOL)
- added support for Ubuntu 22.04

## 0.2.1+1.1.4

- update `runc_version` to `1.1.4`

## 0.2.0+1.1.0

- **BREAKING**: `runc_checksum` isn't a static sha256 sum anymore. It's pointing to the `sha256sum` URL now of a specific release. So it doesn't needs to be adjusted anymore with every new release. The task just downloads the `runc.sha256sum` file and compares checksums.
- update `runc_version` to `1.1.0`
- add Molecule verification via `molecule verify -s kvm`
- add Molecule prepare step
- add `CHANGELOG.md`

## 0.1.0+1.0.2

- initial commit
