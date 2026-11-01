
resource "terraform_data" "upload_file" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = var.host
    private_key = file("${var.repo_root}/.ssh/id_rsa")
  }

  triggers_replace = {
    content_hash = sha256(join("-", [
      var.host,
      var.target_host,
      var.github_access_token,
      var.ssh_host_key
    ]))
  }

  # 秘密を書く前に root だけが読めるファイルを用意しておく (scp は既にあるファイルの権限を変えない)。
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/pve/${var.target_host}",
      "cd /var/lib/pve/${var.target_host} && touch access-tokens-env ssh_host_ed25519_key && chmod 600 access-tokens-env ssh_host_ed25519_key"
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

  # 念のため、書いたあとの権限も確かめて揃える。
  provisioner "remote-exec" {
    inline = [
      "cd /var/lib/pve/${var.target_host} && chmod 600 access-tokens-env ssh_host_ed25519_key"
    ]
  }
}
