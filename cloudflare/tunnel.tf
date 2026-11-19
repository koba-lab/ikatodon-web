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

locals {
  # トンネル経由で受けるホスト名。test_hostname は切り替え前の確認用。
  tunnel_hostnames = [var.hostname, var.test_hostname]

  # Host ヘッダーは常に本体のホスト名で Mastodon に渡す。
  # Mastodon は LOCAL_DOMAIN 以外の Host を拒否するため、確認用ホスト名でもこれが必要。
  origin_request = {
    http_host_header = var.hostname
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "web" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.web.id

  config = {
    # 上から順に評価され、最初に一致したルールが使われる。
    # cloudflared は network_mode: host で動くので、localhost はサーバー自身を指す。
    ingress = concat(
      flatten([
        for host in local.tunnel_hostnames : [
          {
            hostname       = host
            path           = "^/api/v1/streaming"
            service        = "http://localhost:4000"
            origin_request = local.origin_request
          },
          {
            hostname       = host
            path           = null
            service        = "http://localhost:3000"
            origin_request = local.origin_request
          },
        ]
      ]),
      [
        {
          hostname       = null
          path           = null
          service        = "http_status:404"
          origin_request = null
        },
      ],
    )
  }
}
