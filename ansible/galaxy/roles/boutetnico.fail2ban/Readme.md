[![tests](https://github.com/boutetnico/ansible-role-fail2ban/workflows/Test%20ansible%20role/badge.svg)](https://github.com/boutetnico/ansible-role-fail2ban/actions?query=workflow%3A%22Test+ansible+role%22)
[![Ansible Galaxy](https://img.shields.io/badge/galaxy-boutetnico.fail2ban-blue.svg)](https://galaxy.ansible.com/boutetnico/fail2ban)

ansible-role-fail2ban
=====================

This role install and configures [Fail2ban](https://www.fail2ban.org/wiki/index.php/MANUAL_0_8).

Requirements
------------

Ansible 2.10 or newer.

Supported Platforms
-------------------

- [Debian - 11 (Bullseye)](https://wiki.debian.org/DebianBullseye)
- [Debian - 12 (Bookworm)](https://wiki.debian.org/DebianBookworm)
- [Ubuntu - 20.04 (Focal Fossa)](http://releases.ubuntu.com/20.04/)
- [Ubuntu - 22.04 (Jammy Jellyfish)](http://releases.ubuntu.com/22.04/)

Role Variables
--------------

| Variable                | Required | Default               | Choices   | Comments                                       |
|-------------------------|----------|-----------------------|-----------|------------------------------------------------|
| fail2ban_dependencies   | yes      | `[fail2ban]`          | list      |                                                |
| fail2ban_configuration  | yes      | `{}`                  | dict      | Local main configuration.                      |
| fail2ban_jails          | yes      | `{}`                  | dict      | Local jail configuration.                      |
| fail2ban_filters        | yes      | `{}`                  | dict      | Custom filters configuration.                  |
| fail2ban_actions        | yes      | `{}`                  | dict      | Custom actions configuration.                  |

Dependencies
------------

None

Example Playbook
----------------

    - hosts: all
      roles:
        - role: ansible-role-fail2ban

          fail2ban_configuration:
            Definition:
              loglevel: WARNING

          fail2ban_jails:
            DEFAULT:
              ignoreip: 127.0.0.1/8
            nginx-badbots:
              enabled: 'true'
              action: nginx-deny-host[name = nginx-http-auth, port = http, protocol = tcp]
              port: http
              filter: nginx-badbots
              logpath: /var/log/nginx_error.log
              maxretry: 5
              findtime: 600

          fail2ban_filters:
            nginx-badbots:
              Definition:
                _daemon: nginx-badbots
                failregex: |
                  ^ \[error\] \d+#\d+: .* access forbidden by rule, client: <HOST>, .*$
                              FastCGI sent in stderr: "Primary script unknown" .*, client: <HOST>
                ignoreregex: ''

          fail2ban_actions:
            nginx-deny-host:
              Definition:
                actionban: |
                  sed -i "/deny <ip>;/d" <file>
                              echo "deny <ip>;" >> <file>
                              systemctl reload nginx
                actionunban: |
                  sed -i "/deny <ip>;/d" <file>
                                systemctl reload nginx
              Init:
                file: /etc/nginx/hosts.deny

Testing
-------

    molecule test

License
-------

MIT

Author Information
------------------

[@boutetnico](https://github.com/boutetnico)
