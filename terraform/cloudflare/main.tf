locals {
  account_id = "33b475909437e0591f6d9ac47b2a4dd7"
  zone_id    = "f48bce472f942ffe63cd9d992ff7be7d"
  zone_name  = "wpcapp.net"

  # ハニーポット (nuage-honeytrap) に転送する囮のサブドメイン
  # 変更したら nuage-honeytrap の k8s/base/registrar-cronjob.yaml (REGISTRAR_DOMAINS) も揃える
  honeytrap_hostnames = toset([
    "staging-ext",
    "dev-portal",
    "admin-stg",
    "jenkins-dev",
    "vpn-staging",
  ])
  honeytrap_fqdns = sort([for h in local.honeytrap_hostnames : "${h}.${local.zone_name}"])
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

  lifecycle {
    precondition {
      condition     = !startswith(local.zone_id, "PLACEHOLDER")
      error_message = "local.zone_id に実際の Cloudflare Zone ID を設定する必要がある（プレースホルダーのままでは適用不可）。"
    }
  }
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

  lifecycle {
    precondition {
      condition     = !startswith(local.account_id, "PLACEHOLDER")
      error_message = "local.account_id に実際の Cloudflare Account ID を設定する必要がある（プレースホルダーのままでは適用不可）。"
    }
  }
}

# ハニーポット用 Tunnel Ingress ルール設定
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "honeytrap_config" {
  account_id = local.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.honeytrap.id

  config = {
    ingress = concat(
      [
        for fqdn in local.honeytrap_fqdns : {
          hostname = fqdn
          service  = "http://nuage-honeytrap.nuage-honeytrap.svc.cluster.local:80"
        }
      ],
      [
        {
          service = "http_status:404"
        }
      ]
    )
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

# ハニーポット公開用 CNAME レコード (<囮のサブドメイン>.wpcapp.net -> <tunnel_id>.cfargotunnel.com)
# 個別の CNAME はワイルドカード A レコード (*.wpcapp.net) より優先されるので、社内向けの名前には影響しない
resource "cloudflare_dns_record" "honeytrap_cname" {
  for_each = local.honeytrap_hostnames

  zone_id = local.zone_id
  name    = each.key
  content = "${cloudflare_zero_trust_tunnel_cloudflared.honeytrap.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "Cloudflare Tunnel CNAME for nuage-honeytrap"

  lifecycle {
    precondition {
      condition     = !startswith(local.zone_id, "PLACEHOLDER")
      error_message = "local.zone_id に実際の Cloudflare Zone ID を設定する必要がある（プレースホルダーのままでは適用不可）。"
    }
  }
}

# for_each 化する前の単一リソースを staging-ext のキーへ引き継ぎ、レコードの作り直しを防ぐ
moved {
  from = cloudflare_dns_record.honeytrap_cname
  to   = cloudflare_dns_record.honeytrap_cname["staging-ext"]
}

# ハニーポット宛てのリクエストを Cloudflare エッジのセキュリティ機能で弾かず素通しする
# エッジの既定の保護（Browser Integrity Check・Security Level・マネージド WAF 等）が攻撃ボットや
# スキャナーを転送前に遮断し、ハニーポットまで届かなくなるのを防ぐ。
# 対象は local.honeytrap_hostnames の囮ドメインのみ。L7 DDoS 防御は Cloudflare 側で常時有効であり、ここでは切れない。
resource "cloudflare_ruleset" "honeytrap_bypass" {
  zone_id     = local.zone_id
  name        = "nuage-honeytrap bypass"
  description = "ハニーポットの囮ドメイン宛てのリクエストをエッジのセキュリティ機能で検査せず素通しする"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      description = "囮ドメイン宛てをすべて素通し"
      expression  = "(http.host in {${join(" ", [for fqdn in local.honeytrap_fqdns : "\"${fqdn}\""])}})"
      action      = "skip"
      action_parameters = {
        # このフェーズ内の残りのカスタムルール
        ruleset = "current"
        # レート制限ルールとマネージド WAF ルール
        phases = [
          "http_ratelimit",
          "http_request_firewall_managed",
        ]
        # 旧来のセキュリティ機能（BIC・Security Level・User-Agent ブロック等）
        products = [
          "bic",
          "hot",
          "rateLimit",
          "securityLevel",
          "uaBlock",
          "waf",
          "zoneLockdown",
        ]
      }
      enabled = true
    }
  ]

  lifecycle {
    precondition {
      condition     = !startswith(local.zone_id, "PLACEHOLDER")
      error_message = "local.zone_id に実際の Cloudflare Zone ID を設定する必要がある（プレースホルダーのままでは適用不可）。"
    }
  }
}

# Bot Fight Mode と AI クローラーのブロックを無効化する
# Free プランの Bot Fight Mode はホスト単位で skip できないため、ゾーン全体で OFF にする。
# proxied = true なのは囮ドメインの CNAME だけ（`*` は proxied = false）なので、
# ゾーン全体の設定でも実際に影響を受けるのはハニーポットのみである。
resource "cloudflare_bot_management" "honeytrap_bypass" {
  zone_id            = local.zone_id
  fight_mode         = false
  ai_bots_protection = "disabled"

  lifecycle {
    precondition {
      condition     = !startswith(local.zone_id, "PLACEHOLDER")
      error_message = "local.zone_id に実際の Cloudflare Zone ID を設定する必要がある（プレースホルダーのままでは適用不可）。"
    }
  }
}
