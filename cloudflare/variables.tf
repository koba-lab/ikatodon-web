variable "cloudflare_account_id" {
  description = "Cloudflare のアカウント ID。GitHub Actions の変数 CLOUDFLARE_ACCOUNT_ID から渡す"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "queloud.net ゾーンの ID。GitHub Actions の変数 CLOUDFLARE_ZONE_ID から渡す"
  type        = string
}

variable "hostname" {
  description = "イカトドン本体のホスト名（Mastodon の LOCAL_DOMAIN）"
  type        = string
  default     = "ika.queloud.net"
}

variable "media_hostname" {
  description = "メディア配信用のホスト名（/ikatodon-media/ のリダイレクト先。B2 へのパスの書き換えと CORS ヘッダーの対象）"
  type        = string
  default     = "files-ika.queloud.net"
}

variable "tunnel_secret_generation" {
  description = "トンネルの secret の世代。トークンが漏れたときに 1 増やすと secret が作り直される（docs/setup.md）"
  type        = number
  default     = 1
}
