locals {
  dir = "/var/lib/pve/${var.target_host}"
  files = [
    "${local.dir}/access-tokens-env",
    "${local.dir}/sops-key",
  ]

  # 秘密ファイルはコンテナの root だけが読めるようにする。
  # 非特権 LXC ではコンテナの root がホストの UID/GID 100000 に当たるため、持ち主をずらす。
  # ずらさずに 0600 にすると、非特権のコンテナからは読めなくなる。
  mode  = "0600"
  owner = var.unprivileged ? "100000:100000" : "0:0"

  # 持ち主と権限を付け直す。file provisioner は既存のファイルの権限を変えず、
  # 新しく作るときは 0644 で作るため、置く前と後の両方で付ける。
  fix_permissions = [for f in local.files : "touch ${f} && chown ${local.owner} ${f} && chmod ${local.mode} ${f}"]
}

resource "terraform_data" "upload_file" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = var.host
    private_key = file("./../../../.ssh/id_rsa")
  }

  # 権限・持ち主を変えたときも配り直す。
  triggers_replace = {
    content_hash = sha256(join("-", [
      var.host,
      var.target_host,
      var.sops_key,
      var.github_access_token,
      local.mode,
      local.owner,
    ]))
  }

  provisioner "remote-exec" {
    inline = concat(
      ["set -eu", "mkdir -p ${local.dir}"],
      local.fix_permissions,
    )
  }

  provisioner "file" {
    content     = "NIX_CONFIG=access-tokens = github.com=${var.github_access_token}\n"
    destination = "${local.dir}/access-tokens-env"
  }

  provisioner "file" {
    content     = var.sops_key
    destination = "${local.dir}/sops-key"
  }

  provisioner "remote-exec" {
    inline = concat(
      ["set -eu"],
      local.fix_permissions,
      ["stat -c '%a %u:%g %n' ${join(" ", local.files)}"],
    )
  }
}
