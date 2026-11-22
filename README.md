# ikatodon-web

[イカトドン](https://ika.queloud.net/)の Web サーバー周りを管理するリポジトリです。
Mastodon 本体は [koba-lab/mastodon](https://github.com/koba-lab/mastodon)、DB は
[koba-lab/ikatodon-db](https://github.com/koba-lab/ikatodon-db)、Redis は
[koba-lab/ikatodon-redis](https://github.com/koba-lab/ikatodon-redis) で管理しています。

## 構成

```
Client → Cloudflare → (Tunnel) → cloudflared → web (127.0.0.1:3000) / streaming (127.0.0.1:4000)
```

以前は Web サーバーの nginx が 80 / 443 を直接公開していましたが、2026-11-22 に Cloudflare Tunnel と
Cloudflare のルールに置き換えました。Web サーバーは 80 / 443 を開けていません。

## ディレクトリ

| パス                 | 何か                                                 | どこで使うか                       |
| -------------------- | ---------------------------------------------------- | ---------------------------------- |
| `docker-compose.yml` | cloudflared を動かす compose                         | Web サーバー（`docker compose up`） |
| `Dockerfile`         | トンネルのトークン入り cloudflared イメージ          | GitHub Actions（ビルド）           |
| `cloudflare/`        | トンネル、DNS、ルールの Terraform                    | GitHub Actions（plan / apply）     |
| `docs/`              | 手順書と作業記録                                     | 人                                 |

トップレベルはコンテナ関係、`cloudflare/` は Terraform、と分けています。
Web サーバーで使うのは `docker-compose.yml` だけです。

## 手順

- [構築と運用](docs/setup.md)

## 作業記録

- [nginx から Cloudflare Tunnel への移行（2026-11-22）](docs/2026-11-22-cloudflare-tunnel-migration.md)

## 公開リポジトリとしての注意

このリポジトリと GitHub Actions のログは公開されています。IP アドレス、トークン、Terraform の
state をコミットしたりログに出したりしないでください。詳しくは [CLAUDE.md](CLAUDE.md) を参照。
