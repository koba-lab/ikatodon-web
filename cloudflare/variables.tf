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

variable "tunnel_secret_generation" {
  description = "トンネルの secret の世代。トークンが漏れたときに 1 増やすと secret が作り直される（docs/setup.md）"
  type        = number
  default     = 1
}

variable "web_ips" {
  description = <<-EOT
    Web サーバーの IP アドレスをカンマ区切りで並べたもの。GitHub Actions の Secret WEB_IPS から渡す
    （例: 192.0.2.1,192.0.2.2）。公開リポジトリなので、コードにも plan の出力にも出さない。
    並び順が DNS レコードの番号（direct[0], direct[1], ...）になる。順番を入れ替えると
    レコードの中身の書き換えになるので、増減は末尾で行う。
  EOT
  type        = string
  sensitive   = true

  # 空だと A レコードがすべて消える plan になる。Secret の登録漏れで本体が引けなくなるのを防ぐ。
  validation {
    condition     = length(compact([for ip in split(",", var.web_ips) : trimspace(ip)])) > 0
    error_message = "web_ips が空です。GitHub Actions の Secret WEB_IPS を確認してください。"
  }
}

variable "ika_via_tunnel" {
  description = <<-EOT
    本体（hostname）をトンネル経由にするか。
    false: Web サーバーの IP を指す A レコード（DNS only）。nginx が直接受ける
    true:  トンネルを指す CNAME（Proxied）
    切り替えと切り戻しの手順は docs/cutover.md。
  EOT
  type        = bool
  default     = true
}
