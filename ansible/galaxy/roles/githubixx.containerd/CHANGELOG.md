<!--
Copyright (C) 2021-2025 Robert Wimmer
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

## 0.16.0+2.1.4

- **Breaking**
  - `meta/main.yml`: Change `min_ansible_version` to 2.15. Ansible 2.9 is end-of-life (EOL).

- **UPDATE**
  - update `containerd` to `v2.1.4`
  - update `.gitignore`
  - update `.yamllint`
  - fix `ansible-lint` issues

## 0.15.0+2.1.3

- **UPDATE**
  - update `containerd` to `v2.1.3`

- **MOLECULE**
  - Use `generic/arch` Vagrant box instead of `archlinux/archlinux` (no longer available)
  - Install `openssl` package for Archlinux
  - Removed Ubuntu 20.04 because reached end of life

## 0.14.0+2.0.2

**Note**: This a major release update to `containerd` version `2.0.2`! Please read the [changelog of containerd v2.0.2](https://github.com/containerd/containerd/blob/main/docs/containerd-2.0.md) accordingly! In general if you haven't used any "exotic" features so far this version of the Ansible role should cover everything already and upgrading should be smooth. Nevertheless you should test the changes before!

- **POTENTIALLY BREAKING**
  - `containerd_config` variable value was adjusted to to meet `containerd` configuration requirements of version `3`. Please see [Full configuration](https://github.com/containerd/containerd/blob/main/docs/cri/config.md#full-configuration) for all possible values. If you haven't adjusted this variable then there should be no need to change anything and upgrading should be smooth.
  - update list of containerd binaries in `containerd_binaries` variable. `containerd-shim-runc-v1` and `containerd-shim` were removed as no longer provided by upstream.

- **UPDATE**
  - update `containerd` to `v2.0.2`
  - `templates/etc/systemd/system/containerd.service.j2`: add `dbus.service` to `After=`

- **MOLECULE**
  - adjust expected output of `ctr pull` command

## 0.13.2+1.7.22

- **UPDATE**
  - update `containerd` to `v1.7.22`

## 0.13.1+1.7.20

- **UPDATE**
  - update `containerd` to `v1.7.20`

## 0.13.0+1.7.19

- **FEATURE**
  - add support for Ubuntu 24.04

- **UPDATE**
  - update `containerd` to `v1.7.19`

## 0.12.7+1.7.16

- **UPDATE**
  - update `containerd` to `v1.7.16`

## 0.12.6+1.7.15

- **UPDATE**
  - update `containerd` to `v1.7.15`

- **MOLECULE**
  - use `alvistack` instead of `generic` Vagrant boxes

## 0.12.5+1.7.13

- **UPDATE**
  - update `containerd` to `v1.7.13`

## 0.12.4+1.7.12

- add task that creates directory specified in containerd_tmp_directory
- fix typo in defaults/main.yml
- Molecule: Change IP addresses
- Molecule: add two new host variables in `molecule/default/molecule.yml`

## 0.12.3+1.7.12

- update `containerd` to `v1.7.12`
- adjust Github action because of Ansible Galaxy changes

## 0.12.2+1.7.10

- update `containerd` to `v1.7.10`
- remove CNI leftovers

## 0.12.1+1.7.9

- update `containerd` to `v1.7.9`

## 0.12.0+1.7.8

- add missing configuration options to make `containerd` work with Kubernetes out of the box: `[plugins."io.containerd.grpc.v1.cri"]` -> `sandbox_image = "registry.k8s.io/pause:3.8"` and `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc` -> `runtime_type = "io.containerd.runc.v2"`
- add `"Type": "notify"` to `containerd_config`

## 0.11.0+1.7.8

**Note** This release contains quite a few breaking changes. This mostly happened because `cri-containerd-*.tar.gz release bundles` are [deprecated](https://github.com/containerd/containerd/blob/main/RELEASES.md#deprecated-features). Also see [cri-containerd.DEPRECATED.txt](https://github.com/containerd/containerd/blob/main/releases/cri-containerd.DEPRECATED.txt). So `containerd` doesn't contain `CNI plugins` and `runc` anymore. You can still use this bundle if you use version `0.10.0+1.7.3` of this Ansible role. But for this version I decided to remove the support already before `containerd` `v2.0` will be released. That means for `containerd_flavor` only the value `base` can be used and `k8s` has been gone. So that means you have to install [CNI - Container Network Interface](https://github.com/containernetworking/plugins) and [runc](https://github.com/opencontainers/runc) separately. This should happen before you install `containerd`. You can use my Ansible roles

- For CNI: [ansible-role-cni](https://github.com/githubixx/ansible-role-cni)
- For runc: [ansible-role-runc](https://github.com/githubixx/ansible-role-runc)

Other changes:

- **Breaking** `containerd_config` variable contained a complete dump of all possible `containerd` configuration settings. The dump was created with `containerd config default`. So if you just need to execute this command to get all possible configuration options. Since most settings are not relevant I changed the value accordingly and only keep what's different to the default settings. The current settings are intended to be used with a Kubernetes cluster. But in general they should also be a good starting point for standalone installations of `containerd`. If you had your own `containerd_config` variable defined this change doesn't affect you.
- **Breaking** `containerd_flavor` variable only supports `base` value. `k8s` was removed. This variable most probably will be go away in a later release. If you already used `base` value here the change wont affect you.
- **Breaking** `containerd_archive_k8s` variable was removed
- **Breaking** All `runc` related resources and variables were removed: `containerd_runc_binary_directory`, `containerd_runc_owner`, `containerd_runc_group`, `containerd_runc_binary_mode`
- **Breaking** All `crictl`  related resources and variables were removed: `containerd_crictl_config_file`, `containerd_crictl_config_directory`, `containerd_crictl_config_directory_mode`, `containerd_crictl_config_directory_owner`, `containerd_crictl_config_directory_group`, `containerd_crictl_config_file_owner`, `containerd_crictl_config_file_group`, `containerd_crictl_config_file_mode`, `containerd_crictl_config_file_content`
- **Breaking** All `CNI` related resources and variables were removed: `containerd_cni_binary_directory`, `containerd_cni_binary_directory_mode`, `containerd_cni_binary_owner`, `containerd_cni_binary_group`, `containerd_cni_binary_mode`, `containerd_cni_netconfig_file`, `containerd_cni_netconfig_directory`, `containerd_cni_netconfig_directory_mode`, `containerd_cni_netconfig_file_owner`, `containerd_cni_netconfig_file_group`, `containerd_cni_netconfig_file_mode`, `containerd_cni_netconfig_file_content`
- **Breaking** update to containerd configuration version 2 (that means first line in `containerd_config` variable is now `version = 2`)
- update `containerd` to `v1.7.8`
- Molecule: improve verification step
- Molecule: increase memory for boxes
- Molecule: rename `kvm` scenario to `default`

## 0.10.0+1.7.3

- update `containerd` to `v1.7.3`
- add support for Ubuntu 22.04
- **BREAKING**: remove support for Ubuntu 18.04 (reached end of life)
- **BREAKING**: When `containerd` or `CNI` binaries are upgraded `containerd.service` will be restarted. Up until this version this only happened when `containerd` configuration was updated.

## 0.9.0+1.7.0

- update `containerd` to `v1.7.0`
- add Molecule `verify` step

## 0.8.0+1.6.19

- update `containerd` to `v1.6.19`
- fix Molecule `converge.yml`

## 0.7.0+1.6.14

- add Github release action to push new release to Ansible Galaxy

## 0.6.2+1.6.14

- update `containerd` to `v1.6.14`

## 0.6.1+1.6.9

- update `containerd` to `v1.6.9`

## 0.6.0+1.6.8

- fix file permissions in task `Downloading containerd archive`
- ansible-lint: fix issues
- `min_ansible_version` in `meta/main.yml` value should be string
- add `.yamllint`

## 0.5.5+1.6.8

- update `containerd` to `v1.6.8`

## 0.5.4+1.6.6

- update `containerd` to `v1.6.6`

## 0.5.3+1.6.4

- update `containerd` to `v1.6.4`

## 0.5.2+1.6.3

- update `containerd` to `v1.6.3`

## 0.5.1+1.6.2

- update `containerd` to `v1.6.2`

## 0.5.0+1.6.0

- update `containerd` to `v1.6.0`
- update `containerd_config` variable value for containerd `v.1.6.0`

## 0.4.0+1.5.9

- The `BinaryName` value in `container_config` variable will now use the value of `containerd_runc_binary_directory` if defined by default. (contribution by @tiagoblackcode)
- Ansible's `first_found` lookup plugin was used to determine the location of `modprobe` binary. But since all Ansible lookup plugins are only executed on the controller host the modprobe path of the controller host was used in `containerd.service` file. That's fixed now. (contribution by @tiagoblackcode)

## 0.3.0+1.5.9

- In `plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options` the setting `SystemdCgroup` is now set to `true` instead of `false`. This is relevant for Kubernetes e.g. Also see: [Kubernetes container-runtimes - containerd](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd)

## 0.2.1+1.5.9

- update `containerd` to `v1.5.9`

## 0.2.0+1.5.8

- add support for Kubernetes by allowing to optionally also install `runc`, `crictl` and `CNI` plugins. `containerd` builds are available in two flavors: Either just the `containerd` binaries or `containerd` binaries plus everything else needed to use `containerd` together with Kubernetes. Please see [defaults/main.yml](https://github.com/githubixx/ansible-role-containerd/tree/master/defaults/main.yml) for all possible settings. With the Kubernetes support a lot of new variables were introduced but for almost all the default values should be good enough. The default `containerd_flavor: "base"` mimics the behavior of the previous version of this role. So upgrading shouldn't be an issue.

## 0.1.1+1.5.8

- update `containerd` to `v1.5.8`

## 0.1.0+1.5.7

- update `containerd` to `v1.5.7`

## 0.1.0+1.5.5

- initial commit
