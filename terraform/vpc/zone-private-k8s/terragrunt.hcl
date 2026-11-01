include "root" {
  path = find_in_parent_folders("root.hcl")
}
inputs = {
  # .terragrunt-cache ではなく、このディレクトリに書き出す (scripts/bootstrap-cluster.sh が読む)。
  # TODO: 変数をやめ、talosconfig を output にして scripts/bootstrap-cluster.sh が書き出す。
  talosconfig_path = "${get_terragrunt_dir()}/talosconfig"
}
