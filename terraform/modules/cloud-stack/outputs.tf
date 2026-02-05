output "bastion_password" {
  value     = random_password.bastion_password.result
  sensitive = true
}
