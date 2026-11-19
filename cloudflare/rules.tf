# これまで Web サーバーの nginx が担っていた処理を Cloudflare のルールに移す。
#
# ゾーンの各フェーズのルールセット（エントリーポイント）は 1 ゾーンに 1 つしか作れない。
# 管理画面で作ったルールが既にある場合、apply は失敗する。先に import すること（docs/setup.md）。
#
# 本体（ika.queloud.net）はまだ Cloudflare を経由していない（DNS only）ため、
# 切り替えまでは本体に対してこれらのルールは効かない。

locals {
  # 例: http.host in {"ika.queloud.net" "ika-tunnel-test.queloud.net"}
  host_expression = "http.host in {${join(" ", formatlist("\"%s\"", local.tunnel_hostnames))}}"
}

# アプリ・API 経由の新規登録（POST /api/v1/accounts）を遮断する。
# 経緯は koba-lab/mastodon の ikatodon/docs/infrastructure.md 4.3 節。
# GET /api/v1/accounts は通す。Rails は末尾スラッシュを無視するため /api/v1/accounts/ も塞ぐ。
resource "cloudflare_ruleset" "firewall_custom" {
  zone_id = var.cloudflare_zone_id
  name    = "ikatodon-web firewall custom rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      description = "Block account sign-up via API"
      expression  = "(${local.host_expression} and http.request.method eq \"POST\" and http.request.uri.path in {\"/api/v1/accounts\" \"/api/v1/accounts/\"})"
      action      = "block"
      enabled     = true
    },
  ]
}

# 旧メディア URL（/ikatodon-media/...）をメディア配信用ホストへリダイレクトする。
resource "cloudflare_ruleset" "redirect" {
  zone_id = var.cloudflare_zone_id
  name    = "ikatodon-web redirects"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      description = "Redirect legacy media URLs"
      expression  = "(${local.host_expression} and starts_with(http.request.uri.path, \"/ikatodon-media/\"))"
      action      = "redirect"
      enabled     = true
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url = {
            expression = "wildcard_replace(http.request.uri.path, \"/ikatodon-media/*\", \"https://${var.media_hostname}/$${1}\")"
          }
        }
      }
    },
  ]
}

# クライアントが送ってきた Forwarded / Proxy ヘッダーをオリジンに渡さない。
# 上流 Mastodon の dist/nginx.conf が `proxy_set_header Forwarded "";` と
# `proxy_set_header Proxy "";` で行っている処理と同じ（Forwarded は上流 #41481、Proxy は httpoxy 対策）。
resource "cloudflare_ruleset" "request_header_transform" {
  zone_id = var.cloudflare_zone_id
  name    = "ikatodon-web request header transforms"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [
    {
      description = "Strip Forwarded and Proxy request headers"
      expression  = local.host_expression
      action      = "rewrite"
      enabled     = true
      action_parameters = {
        headers = {
          "Forwarded" = { operation = "remove" }
          "Proxy"     = { operation = "remove" }
        }
      }
    },
  ]
}
