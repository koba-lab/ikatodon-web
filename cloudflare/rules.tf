# 以前 Web サーバーの nginx が担っていた処理を Cloudflare のルールで行う。
#
# ゾーンの各フェーズのルールセット（エントリーポイント）は 1 ゾーンに 1 つしか作れない。
# 管理画面で作ったルールが既にある場合、apply は失敗する。先に import すること（docs/setup.md）。

locals {
  host_expression = "http.host eq \"${var.hostname}\""
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

# クライアントが送ってきた Forwarded ヘッダーをオリジンに渡さない。
# 上流 Mastodon の dist/nginx.conf の `proxy_set_header Forwarded "";` と同じ（上流 #41481）。
#
# dist/nginx.conf は Proxy ヘッダーも消している（httpoxy 対策）が、Cloudflare の Transform Rules では
# Proxy ヘッダーを操作できない（API が code 20087 で拒否する）。httpoxy は CGI 環境で HTTP_PROXY 環境変数に
# 化ける問題で、Puma（Rack）で動く Mastodon は環境変数ではなく Rack env に入るため影響しない。
resource "cloudflare_ruleset" "request_header_transform" {
  zone_id = var.cloudflare_zone_id
  name    = "ikatodon-web request header transforms"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [
    {
      description = "Strip Forwarded request header"
      expression  = local.host_expression
      action      = "rewrite"
      enabled     = true
      action_parameters = {
        headers = {
          "Forwarded" = { operation = "remove" }
        }
      }
    },
  ]
}
