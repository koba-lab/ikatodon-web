# 本体（ika.queloud.net）はトンネルを指す CNAME。
resource "cloudflare_dns_record" "ika" {
  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "ikatodon-web: トンネル経由（Terraform 管理）"
}
