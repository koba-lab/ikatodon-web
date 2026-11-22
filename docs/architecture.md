# 構成

イカトドンの Web サーバー周りが今どうなっていて、なぜそうしているかをまとめます。構成を変えたら
この文書も書き換えます。手順は [setup.md](setup.md) にあります。

## 全体

```
Client → Cloudflare → (Tunnel) → cloudflared（各 Web サーバー） → web (127.0.0.1:3000) / streaming (127.0.0.1:4000)
```

- 本体（`ika.queloud.net`）の DNS は、トンネルを指す Proxied の CNAME（`cloudflare/dns.tf`）
- Web サーバー 2 台の cloudflared が同じトンネルに接続し、Cloudflare が両方へ振り分ける
- cloudflared は Cloudflare へ外向きに接続するだけで、Web サーバーは外からの接続を受け付けない

2026-11-22 までは、各 Web サーバーの nginx が 80 / 443 を直接公開していました。nginx の脆弱性
（NGINX2Root）をきっかけに置き換えました。経緯は koba-lab/mastodon の
`ikatodon/docs/infrastructure.md` にあります。

## 処理の担当

nginx が担っていた処理は、次のところで行っています。

| 処理                                                        | 担当                                            |
| ----------------------------------------------------------- | ----------------------------------------------- |
| TLS の終端                                                  | Cloudflare                                      |
| `/api/v1/streaming` を streaming へ振り分け                  | トンネルの ingress（`cloudflare/tunnel.tf`）    |
| アプリ・API 経由の新規登録（`POST /api/v1/accounts`）の遮断 | WAF のカスタムルール（`cloudflare/rules.tf`）   |
| 旧メディア URL（`/ikatodon-media/`）のリダイレクト          | Redirect Rules（`cloudflare/rules.tf`）         |
| `Forwarded` ヘッダーの除去                                  | Request Header Transform（`cloudflare/rules.tf`） |

次のものは持っていません。

- **メンテナンスモード**（nginx の `geo $allow_ip` で、許可した IP 以外を止める仕組み）。使う予定がない
  ため移しませんでした。必要になったら Cloudflare 側で用意します
- **API 登録の遮断の独自レスポンス**。nginx では JSON のエラーメッセージを返していましたが、
  Cloudflare の WAF で独自のレスポンスを返すには Pro プラン以上が要るため、Cloudflare 標準の 403
  ページを返しています

## Host ヘッダー

トンネルは Host ヘッダーを書き換えません（ingress に `httpHostHeader` を設定しない）。クライアントが
送った Host（`ika.queloud.net`）のまま Mastodon に届き、Mastodon の Host チェック
（`config/initializers/1_hosts.rb`）を通ります。

`httpHostHeader` を設定しても、cloudflared は書き換え前の Host を `X-Forwarded-Host` に入れて送ります
（cloudflared 2026.10.7 の `ingress/origin_proxy.go`）。Rails は `X-Forwarded-Host` を `request.host`
として扱うので、書き換えは効きません。

## クライアント IP

Mastodon（Rails）は利用者の IP を `X-Forwarded-For` から取ります。

- Cloudflare は `X-Forwarded-For` の右端に、Cloudflare に接続してきた IP を足してオリジンに送る。
  右端が本物で、それより左は利用者が自由に書ける
  （[Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)）
- Rails（`ActionDispatch::RemoteIp`）は `X-Forwarded-For` を右から見て、信頼するプロキシ（既定では
  ループバックとプライベートアドレス）を飛ばし、最初に出てきた IP を利用者の IP にする
- cloudflared はサーバー上から `localhost:3000` に接続するので、Mastodon から見た接続元は信頼する
  プロキシの範囲に入る
- 本番の `.env.production` に `TRUSTED_PROXY_IP` はない。設定すると信頼する範囲が変わるので、
  設定するときはこの前提を見直す

Cloudflare は `CF-Connecting-IP` を使うよう勧めていますが、Mastodon は読みません（読ませるには
上流のコードの変更が要る）。Tunnel 経由でも `X-Forwarded-For` が付くことは Cloudflare のドキュメントに
明記されていないため、cloudflared を更新したら [setup.md](setup.md) の「クライアント IP の確認」を
行います。

## DNS

- 本体の CNAME は Proxied で、TTL は Cloudflare が 300 秒に固定する
- `ika.queloud.net` には Google Search Console のサイト確認用の TXT レコードがある（管理画面で管理）。
  Proxied の CNAME と同じ名前でも引ける
- このゾーンでは SOA を変更できない（API が `Custom SOA records are not available to this account or zone`
  を返す）

## Web サーバー側の状態

このリポジトリの外で設定しているものです。サーバーを足したり作り直したりするときは合わせます。

- nginx は停止し、自動起動も無効にしてある
- Let's Encrypt の証明書の更新は止めてある（`certbot.timer` を無効にし、crontab の `certbot renew` の行を
  コメントアウト）。crontab の行は `service nginx restart` を含むので、戻すと nginx が起動する
- ConoHa の接続許可ポートは SSH だけ（80 / 443 は開けない）
- Docker は自動起動が有効。cloudflared は `restart: always` なので、サーバーを再起動しても上がる
