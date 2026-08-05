data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.yaml"
}

locals {
  secrets = data.sops_file.secrets.data
  zone_id = local.secrets["cloudflare_zone_id"]
}

# ワイルドカード A レコード (*.wpcapp.net -> 192.168.5.200)
resource "cloudflare_dns_record" "wildcard_a" {
  zone_id = local.zone_id
  name    = "*"
  content = "192.168.5.200"
  type    = "A"
  ttl     = 1 # 1 = Automatic
  proxied = false
  comment = "Wildcard A record for internal k8s services"
}

# ルートドメイン A レコード (wpcapp.net -> 192.168.5.200)
# 必要に応じてコメントアウトを解除して使用
# resource "cloudflare_dns_record" "root_a" {
#   zone_id = local.zone_id
#   name    = "@"
#   content = "192.168.5.200"
#   type    = "A"
#   ttl     = 1
#   proxied = false
#   comment = "Root A record for wpcapp.net"
# }
