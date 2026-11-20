# 確認用ホスト名は常にトンネルに向ける。
resource "cloudflare_dns_record" "test" {
  zone_id = var.cloudflare_zone_id
  name    = var.test_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "ikatodon-web: トンネル動作確認用（Terraform 管理）"
}

# 本体（ika.queloud.net）は var.ika_via_tunnel で向け先を切り替える。
#
# 同じ名前に A レコードと CNAME は共存できない。tunnel に depends_on を付けると、
# 切り替え（A → CNAME）でも切り戻し（CNAME → A）でも「古いほうを消してから新しいほうを作る」
# 順になる（Terraform 1.16.7 で確認）。消してから作るまでの 1 秒前後はレコードが無い
# （影響と対応は docs/cutover.md）。

locals {
  # カンマ区切りの Secret を配列にする（前後の空白と空の要素は捨てる）
  web_ips = compact([for ip in split(",", var.web_ips) : trimspace(ip)])
}

resource "cloudflare_dns_record" "direct" {
  # 台数だけを sensitive から外す。台数は秘密ではなく、count には sensitive な値を使えないため。
  count = var.ika_via_tunnel ? 0 : nonsensitive(length(local.web_ips))

  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "A"
  content = local.web_ips[count.index]
  proxied = false
  # 切り戻しをすぐ効かせるため短くしておく（DNS only で設定できる最小値）
  ttl     = 60
  comment = "ikatodon-web: Web サーバーへ直接（Terraform 管理）"
}

resource "cloudflare_dns_record" "tunnel" {
  count = var.ika_via_tunnel ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.web.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "ikatodon-web: トンネル経由（Terraform 管理）"

  depends_on = [cloudflare_dns_record.direct]
}

# 切り替え前の確認用。Proxied の CNAME と同じ名前に置いた TXT が引けるかを確かめる。
# 本体の ika.queloud.net には Google Search Console の確認用 TXT があり、CNAME（Proxied）に
# 切り替えると引けなくなる可能性がある（Cloudflare の DNS record types の Proxied CNAME records）。
# 確かめ終わったら消す。
resource "cloudflare_dns_record" "test_txt" {
  zone_id = var.cloudflare_zone_id
  name    = var.test_hostname
  type    = "TXT"
  content = "\"ikatodon-web-txt-test\""
  ttl     = 1
  comment = "ikatodon-web: Proxied CNAME と TXT の共存確認用（確認後に削除）"
}
