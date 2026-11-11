locals {
  account_id = "PLACEHOLDER_CLOUDFLARE_ACCOUNT_ID" # 人間が記入
  zone_id    = "PLACEHOLDER_CLOUDFLARE_ZONE_ID"    # 人間が記入
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

# ハニーポット用 Cloudflare Tunnel Secret
resource "random_id" "tunnel_secret" {
  byte_length = 35
}

# ハニーポット用 Cloudflare Zero Trust Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "honeytrap" {
  account_id    = local.account_id
  name          = "nuage-honeytrap-ext"
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# ハニーポット用 Tunnel Ingress ルール設定
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "honeytrap_config" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.honeytrap.id

  config = {
    ingress = [
      {
        hostname = "staging.ext.wpcapp.net"
        service  = "http://nuage-honeytrap.nuage-honeytrap.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

# ハニーポット用 Tunnel Token 取得
data "cloudflare_zero_trust_tunnel_cloudflared_token" "honeytrap_token" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.honeytrap.id
}

output "honeytrap_tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.honeytrap_token.token
  sensitive = true
}

# ハニーポット公開用 CNAME レコード (staging.ext.wpcapp.net -> <tunnel_id>.cfargotunnel.com)
resource "cloudflare_dns_record" "honeytrap_cname" {
  zone_id = local.zone_id
  name    = "staging.ext"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.honeytrap.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "Cloudflare Tunnel CNAME for nuage-honeytrap"
}
