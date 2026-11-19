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

variable "test_hostname" {
  description = "切り替え前にトンネル経由の動作を確かめるためのホスト名"
  type        = string
  default     = "ika-tunnel-test.queloud.net"
}

variable "media_hostname" {
  description = "メディア配信用のホスト名（/ikatodon-media/ のリダイレクト先）"
  type        = string
  default     = "files-ika.queloud.net"
}
