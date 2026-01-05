variable "ansible_ssh_private_key" {
  description = "Private SSH key for Ansible connections (from 1Password)"
  type        = string
  sensitive   = true
}
