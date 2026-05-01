include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common_secrets = read_terragrunt_config(find_in_parent_folders("secrets.hcl"))
}

inputs = {
  cloudflare_account_id = local.common_secrets.inputs.cloudflare_account_id
}
