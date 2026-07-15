
resource "terraform_data" "upload_file" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = var.host
    private_key = file("./../../../.ssh/id_rsa")
  }

  triggers_replace = {
    content_hash = sha256(join("-", [
      var.host,
      var.target_host,
      var.sops_key,
      var.github_access_token
    ]))
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/pve/${var.target_host}"
    ]
  }

  provisioner "file" {
    content     = "NIX_CONFIG=access-tokens = github.com=${var.github_access_token}\n"
    destination = "/var/lib/pve/${var.target_host}/access-tokens-env"
  }

  provisioner "file" {
    content     = var.sops_key
    destination = "/var/lib/pve/${var.target_host}/sops-key"
  }
}
