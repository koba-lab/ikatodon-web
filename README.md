# ikatodon-web

[イカトドン](https://ika.queloud.net/)の Web サーバー周りを管理するリポジトリです。
Mastodon 本体は [koba-lab/mastodon](https://github.com/koba-lab/mastodon)、DB は
[koba-lab/ikatodon-db](https://github.com/koba-lab/ikatodon-db)、Redis は
[koba-lab/ikatodon-redis](https://github.com/koba-lab/ikatodon-redis) で管理しています。

## 構成

```
Client → Cloudflare → (Tunnel) → cloudflared → web (127.0.0.1:3000) / streaming (127.0.0.1:4000)
```

詳しくは [構成](docs/architecture.md) を参照してください。

## ディレクトリ

| パス                 | 何か                                                 | どこで使うか                       |
| -------------------- | ---------------------------------------------------- | ---------------------------------- |
| `docker-compose.yml` | cloudflared を動かす compose                         | Web サーバー（`docker compose up`） |
| `Dockerfile`         | トンネルのトークン入り cloudflared イメージ          | GitHub Actions（ビルド）           |
| `cloudflare/`        | トンネル、DNS、ルールの Terraform                    | GitHub Actions（plan / apply）     |
| `docs/`              | 構成の説明と手順書                                   | 人                                 |

トップレベルはコンテナ関係、`cloudflare/` は Terraform、と分けています。
Web サーバーで使うのは `docker-compose.yml` だけです。

## 手順

- [構築と運用](docs/setup.md)

## 公開リポジトリとしての注意

このリポジトリと GitHub Actions のログは公開されています。IP アドレス、トークン、Terraform の
state をコミットしたりログに出したりしないでください。詳しくは [CLAUDE.md](CLAUDE.md) を参照。
