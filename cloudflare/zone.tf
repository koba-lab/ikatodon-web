# queloud.net ゾーンの DNS 設定。
#
# 本体の向け先を切り替えるとき（docs/cutover.md）、A レコードを消してから CNAME を作るまでの
# 数秒はレコードが無い。その瞬間に引いたリゾルバーは「存在しない」という答えを SOA の
# Minimum TTL（min_ttl）の間キャッシュするので、既定の 1800 秒から 60 秒に下げておく。
# nginx を止めて切り戻しの必要がなくなったら 1800 に戻す。
#
# このリソースは import できず、作ると既存の設定を上書きする。書いていない項目が既定値に
# 戻らないよう、min_ttl 以外は 2026-11 時点の値（API の dns_settings）をそのまま書き写している。
resource "cloudflare_zone_dns_settings" "this" {
  zone_id = var.cloudflare_zone_id

  flatten_all_cnames  = false
  foundation_dns      = false
  multi_provider      = false
  secondary_overrides = false
  zone_mode           = "standard"
  ns_ttl              = 86400

  nameservers = {
    type = "cloudflare.standard"
  }

  soa = {
    rname   = "dns.cloudflare.com"
    refresh = 10000
    retry   = 2400
    expire  = 604800
    min_ttl = 60
    ttl     = 3600
  }
}
