# Semaphore Infra Project Management

resource "semaphoreui_project" "infra" {
  name = "Infra"
}

resource "semaphoreui_project_key" "none" {
  project_id = semaphoreui_project.infra.id
  name       = "None"
  none       = {}
}

resource "semaphoreui_project_key" "ansible_ssh" {
  project_id = semaphoreui_project.infra.id
  name       = "ansible-ssh"
  ssh = {
    private_key = var.ansible_ssh_private_key
  }
}

resource "semaphoreui_project_repository" "infra" {
  project_id = semaphoreui_project.infra.id
  name       = "claytono/infra"
  url        = "https://github.com/claytono/infra"
  branch     = "main"
  ssh_key_id = semaphoreui_project_key.none.id
}

resource "semaphoreui_project_inventory" "default" {
  project_id = semaphoreui_project.infra.id
  name       = "default"
  ssh_key_id = semaphoreui_project_key.ansible_ssh.id
  file = {
    path          = "ansible/inventory/default"
    repository_id = semaphoreui_project_repository.infra.id
  }
}

resource "semaphoreui_project_environment" "empty" {
  project_id  = semaphoreui_project.infra.id
  name        = "Empty"
  environment = {}
}

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
