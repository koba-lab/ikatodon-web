# Web サーバー 2 台の cloudflared が同じトンネルに接続し、Cloudflare が両方へ振り分ける。

resource "random_bytes" "tunnel_secret" {
  length = 32

  keepers = {
    generation = var.tunnel_secret_generation
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "web" {
  account_id = var.cloudflare_account_id
  name       = "ikatodon-web"

  # ingress をサーバー上の設定ファイルではなく Cloudflare 側（下の _config リソース）で管理する。
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "web" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.web.id

  config = {
    # 上から順に評価され、最初に一致したルールが使われる。
    # cloudflared は network_mode: host で動くので、localhost はサーバー自身を指す。
    #
    # Host ヘッダーは書き換えない（httpHostHeader を使わない）。クライアントが送った Host
    # （ika.queloud.net）のまま Mastodon に届く。httpHostHeader を設定すると cloudflared は元の
    # Host を X-Forwarded-Host に入れ、Rails はそちらを Host として扱うため、書き換えの意味がない。
    ingress = [
      {
        hostname = var.hostname
        path     = "^/api/v1/streaming"
        service  = "http://localhost:4000"
      },
      {
        hostname = var.hostname
        path     = null
        service  = "http://localhost:3000"
      },
      {
        hostname = null
        path     = null
        service  = "http_status:404"
      },
    ]
  }
}
