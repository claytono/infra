# Semaphore Infra Project Management
#
# Existing Resource IDs (discovered via API):
#   Project: 2
#   Repository: 2
#   Keys: 3 (None), 5 (ansible-ssh)
#   Inventory: 6 (default)
#   Environment: 2 (Empty)
#   Template: 9 (Ansible deploy to all)

# Import: tofu import module.semaphore.semaphoreui_project.infra project/2
resource "semaphoreui_project" "infra" {
  name = "Infra"
}

# Import: tofu import module.semaphore.semaphoreui_project_key.none project/2/key/3
resource "semaphoreui_project_key" "none" {
  project_id = semaphoreui_project.infra.id
  name       = "None"
  none       = {}
}

# Import: tofu import module.semaphore.semaphoreui_project_key.ansible_ssh project/2/key/5
resource "semaphoreui_project_key" "ansible_ssh" {
  project_id = semaphoreui_project.infra.id
  name       = "ansible-ssh"
  ssh = {
    private_key = var.ansible_ssh_private_key
  }
}

# Import: tofu import module.semaphore.semaphoreui_project_repository.infra project/2/repository/2
resource "semaphoreui_project_repository" "infra" {
  project_id = semaphoreui_project.infra.id
  name       = "claytono/infra"
  url        = "https://github.com/claytono/infra"
  branch     = "main"
  ssh_key_id = semaphoreui_project_key.none.id
}

# Import: tofu import module.semaphore.semaphoreui_project_inventory.default project/2/inventory/6
resource "semaphoreui_project_inventory" "default" {
  project_id = semaphoreui_project.infra.id
  name       = "default"
  ssh_key_id = semaphoreui_project_key.ansible_ssh.id
  file = {
    path          = "ansible/inventory/default"
    repository_id = semaphoreui_project_repository.infra.id
  }
}

# Import: tofu import module.semaphore.semaphoreui_project_environment.empty project/2/environment/2
resource "semaphoreui_project_environment" "empty" {
  project_id  = semaphoreui_project.infra.id
  name        = "Empty"
  environment = {}
}

# Import: tofu import module.semaphore.semaphoreui_project_template.ansible_deploy project/2/template/9
resource "semaphoreui_project_template" "ansible_deploy" {
  project_id                  = semaphoreui_project.infra.id
  name                        = "ansible-deploy"
  description                 = "Run site.yaml - pass --limit and --tags via CLI args"
  playbook                    = "site.yaml"
  repository_id               = semaphoreui_project_repository.infra.id
  inventory_id                = semaphoreui_project_inventory.default.id
  environment_id              = semaphoreui_project_environment.empty.id
  app                         = "ansible"
  allow_override_args_in_task = true
}
