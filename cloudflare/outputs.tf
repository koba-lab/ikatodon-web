output "tunnel_id" {
  description = "トンネルの ID（秘密情報ではない）"
  value       = cloudflare_zero_trust_tunnel_cloudflared.web.id
}
