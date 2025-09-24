import pytest

import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ["MOLECULE_INVENTORY_FILE"]
).get_hosts("all")


@pytest.mark.parametrize(
    "name",
    [
        ("fail2ban"),
    ],
)
def test_packages_are_installed(host, name):
    package = host.package(name)
    assert package.is_installed


@pytest.mark.parametrize(
    "path,user,group,mode",
    [
        ("/etc/fail2ban/fail2ban.local", "root", "root", 0o644),
        ("/etc/fail2ban/jail.local", "root", "root", 0o644),
        ("/etc/fail2ban/filter.d/nginx-badbots.conf", "root", "root", 0o644),
        ("/etc/fail2ban/action.d/nginx-deny-host.conf", "root", "root", 0o644),
    ],
)
def test_auth_file_exists(host, path, user, group, mode):
    path = host.file(path)
    assert path.exists
    assert path.is_file
    assert path.user == user
    assert path.group == group
    assert path.mode == mode


@pytest.mark.parametrize(
    "name",
    [
        ("fail2ban"),
    ],
)
def test_service_is_running_and_enabled(host, name):
    service = host.service(name)
    assert service.is_enabled
    assert service.is_running
