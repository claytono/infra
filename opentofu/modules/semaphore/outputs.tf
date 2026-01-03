output "project_id" {
  description = "Semaphore project ID for API calls"
  value       = semaphoreui_project.infra.id
}

output "project_name" {
  description = "Semaphore project name"
  value       = semaphoreui_project.infra.name
}

output "template_id" {
  description = "Template ID for triggering Ansible runs"
  value       = semaphoreui_project_template.ansible_deploy.id
}

output "template_name" {
  description = "Template name for triggering Ansible runs"
  value       = semaphoreui_project_template.ansible_deploy.name
}
