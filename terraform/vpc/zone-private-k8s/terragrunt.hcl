include "root" {
  path = find_in_parent_folders("root.hcl")
}
inputs = {
  # .terragrunt-cache ではなく、このディレクトリに書き出す (scripts/bootstrap-cluster.sh が読む)。
  talosconfig_path = "${get_terragrunt_dir()}/talosconfig"
}
