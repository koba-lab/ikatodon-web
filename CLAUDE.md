# ikatodon-web

イカトドンの Web サーバー周り（Cloudflare Tunnel、Cloudflare のルール、Web サーバー上のコンテナ）を
管理するリポジトリです。Mastodon 本体は koba-lab/mastodon、DB は koba-lab/ikatodon-db、
Redis は koba-lab/ikatodon-redis にあります。

## 最重要: このリポジトリは公開されている

リポジトリも GitHub Actions のログも誰でも見られます。

- **IP アドレスを書かない。** サーバーの IP も、運営者の許可 IP も、コード・ドキュメント・
  コミットメッセージ・PR 本文に書かない。必要な値は GitHub Actions の Secret / 変数から渡す
- **Terraform の state をコミットしない。** state にはトンネルの secret などが平文で入る。
  state は R2 にだけ置く
- **秘密情報を含む Terraform 変数には `sensitive = true` を付ける。** 付けないと plan の出力
  （公開ログ）に値が出る
- **plan ファイルや state を artifact に上げない。** 公開リポジトリの artifact は誰でも
  ダウンロードできる
- **`pull_request_target` を使わない。** フォークからの PR に Secret を渡さないため
- **トンネルのトークンが入ったイメージ（`ghcr.io/koba-lab/ikatodon-tunnel`）は必ず Private。**
  トークンがあれば偽のコネクタを立てて本番のトラフィックを受け取れる

## 方針: YAGNI

今必要なものだけを作ります。

- 起きていない問題への保険、念のための多重化、将来の拡張に備えた仕組みは入れない
- 必要になったら、そのときに足す
- 消せるものは消す（使い終わった一時的な設定、効いていない設定）

レビュー（人、CodeRabbit、Copilot など）の指摘も同じ基準で判断します。指摘が技術的に正しくても、
今の問題を解決しない追加（保険・多重化・将来への備え）は対応せず、理由を返信して見送ります。

## ディレクトリの決まり

- トップレベル: コンテナ関係（`Dockerfile`、`docker-compose.yml`）
- `cloudflare/`: Cloudflare に適用する Terraform
- `docs/`: 手順書

Web サーバーで使うのはトップレベルの `docker-compose.yml` だけです。新しい適用先
（例: ConoHa）を Terraform で管理するときは、`cloudflare/` と並べてディレクトリを足します。

## ブランチと PR

- デフォルトブランチは `main`。変更は PR で入れる
- `cloudflare/` を変える PR では、CI の plan の結果を確認してからマージする
- `main` へのマージで apply が走る。apply は Environment `production` の承認が必要

## 検証

```bash
terraform -chdir=cloudflare fmt -check -recursive
terraform -chdir=cloudflare init -backend=false
terraform -chdir=cloudflare validate
```

## ドキュメントの言語

ドキュメント、コメント、コミットメッセージ、PR は日本語で書きます。
