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

# 移行中の count 付きリソースからの名前の付け替え。apply が済んだら消してよい。
moved {
  from = cloudflare_dns_record.tunnel[0]
  to   = cloudflare_dns_record.ika
}
