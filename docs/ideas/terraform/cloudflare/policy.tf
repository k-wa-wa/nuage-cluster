# Traffic settings で proxy traffic を有効にする必要あり

resource "cloudflare_zero_trust_gateway_policy" "waai_allow" {
  account_id = local.cloudflare_account_id
  name       = "allow zone-waai"
  precedence = 1000
  action     = "allow"
  filters    = ["l4"]
  identity   = "identity.email in {\"sek.ohei.w0822@icloud.com\" \"koohee2280w@gmail.com\"}"
  traffic    = "net.dst.ip in {10.30.1.0/24}"
  enabled    = true
}

resource "cloudflare_zero_trust_gateway_policy" "strict_default_deny" {
  account_id = local.cloudflare_account_id
  name       = "Strict Deny All Private Traffic"
  precedence = 9999
  action     = "block"
  filters    = ["l4"]
  traffic    = "net.dst.ip in {0.0.0.0/0}"
  enabled    = true
}
