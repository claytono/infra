output "project_name" {
  description = "Semaphore project name"
  value       = semaphoreui_project.infra.name
}

output "template_name" {
  description = "Template name for triggering Ansible runs"
  value       = semaphoreui_project_template.ansible_deploy.name
}
