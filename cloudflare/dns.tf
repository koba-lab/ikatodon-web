# 切り替え前の確認用ホスト名だけをトンネルに向ける。
# 本体（ika.queloud.net）の向け替えは docs/cutover.md の手順で別の PR として行う。

resource "cloudflare_dns_record" "test" {
  zone_id = var.cloudflare_zone_id
  name    = var.test_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "ikatodon-web: トンネル動作確認用（Terraform 管理）"
}
