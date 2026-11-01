locals {
  files = "access-tokens-env ssh_host_ed25519_key"

  # 持ち主はコンテナの root にする。非特権 LXC ではコンテナの root がホストの UID/GID 100000 に当たる。
  # 持ち主がホストの root (0) のまま 0600 だとコンテナの root から読めず、sshd と sops-nix が鍵を読めない。
  # 特権に戻したときに 100000 のまま残らないよう、特権でも 0:0 を付け直す。
  owner = var.unprivileged ? "100000:100000" : "0:0"

  # 持ち主は非特権のときだけ trigger に入れる。特権のホストでは今までと同じ値になり、配り直しが起きない。
  trigger_owner = var.unprivileged ? [local.owner] : []
}

resource "terraform_data" "upload_file" {
  connection {
    type = "ssh"
    user = "root"
    host = var.host
    # Proxmox の root に入る鍵は ssh-agent から使う。apply の前に ssh-add .ssh/keys/pve-root を打つ
    # (鍵は .ssh/login-keys.yaml の pve-root。scripts/gen-login-key.sh が作る)。
    agent = true
  }

  triggers_replace = {
    content_hash = sha256(join("-", concat([
      var.host,
      var.target_host,
      var.github_access_token,
      var.ssh_host_key
    ], local.trigger_owner)))
  }

  # 秘密を書く前に root だけが読めるファイルを用意しておく (scp は既にあるファイルの権限を変えない)。
  # 持ち主を変えるのは権限を絞ってからにし、他のユーザーから読める瞬間を作らない。
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/pve/${var.target_host}",
      "cd /var/lib/pve/${var.target_host} && touch ${local.files} && chmod 600 ${local.files} && chown ${local.owner} ${local.files}"
    ]
  }

  provisioner "file" {
    content     = "NIX_CONFIG=access-tokens = github.com=${var.github_access_token}\n"
    destination = "/var/lib/pve/${var.target_host}/access-tokens-env"
  }

  provisioner "file" {
    content     = var.ssh_host_key
    destination = "/var/lib/pve/${var.target_host}/ssh_host_ed25519_key"
  }

  # 念のため、書いたあとの権限と持ち主も確かめて揃える。
  provisioner "remote-exec" {
    inline = [
      "cd /var/lib/pve/${var.target_host} && chmod 600 ${local.files} && chown ${local.owner} ${local.files} && stat -c '%a %u:%g %n' ${local.files}"
    ]
  }
}
