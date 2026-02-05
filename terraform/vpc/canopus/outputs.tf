output "bastion_password" {
  value     = module.cloud_stack.bastion_password
  sensitive = true
}
