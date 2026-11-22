# nginx から Cloudflare Tunnel への移行（2026-11-22）

イカトドンの Web サーバーの前段を、nginx から Cloudflare Tunnel に置き換えた作業の記録です。
後から経緯と判断の理由を追えるように残します。時刻は日本時間です。

## 背景

- 2026-11-18 に nginx の脆弱性 NGINX2Root（CVE-2026-123007 / CVE-2026-123633、HTTP/2 に起因する
  リモートコード実行）が公開された
- 当時の Web サーバー 2 台は、Cloudflare を経由せず、nginx で 80 / 443 を直接公開していた
- 2026-11-19 に暫定対策として、2 台の nginx の設定から `http2` を外した
  （koba-lab/mastodon の `ikatodon/docs/infrastructure.md` 4.5 節）
- 恒久対策として nginx をやめ、Cloudflare Tunnel に置き換えることにした。Web サーバーが外から
  接続を受け付けなくなり、nginx の脆弱性対応も不要になる

## 移行前と移行後

移行前:

```
Client → (DNS ラウンドロビン、DNS only) → nginx（各 Web サーバー、80 / 443） → web / streaming
```

移行後:

```
Client → Cloudflare → (Tunnel) → cloudflared（各 Web サーバー） → web (127.0.0.1:3000) / streaming (127.0.0.1:4000)
```

nginx が担っていた処理は次のように移した。

- TLS の終端: Cloudflare（Let's Encrypt の証明書は不要になった）
- `/api/v1/streaming` の振り分け: トンネルの ingress（`cloudflare/tunnel.tf`）
- アプリ・API 経由の新規登録（`POST /api/v1/accounts`）の遮断: WAF のカスタムルール（`cloudflare/rules.tf`）
- 旧メディア URL（`/ikatodon-media/`）のリダイレクト: Redirect Rules（同上）
- `Forwarded` ヘッダーの除去: Request Header Transform（同上）
- メンテナンスモード（`geo $allow_ip` による許可 IP 以外の遮断）: 移さなかった。直近で使う予定がない。
  必要になったら、そのときに Cloudflare 側で用意する

## 経過

- 11-19: リポジトリを作り、トンネル、ルール、イメージのビルドを用意した（#1、#9、#10、#11）
- 11-21: cloudflared がトークンのファイルを読めずに起動しない問題を直した（#12）。2 台で起動し、
  確認用ホスト名（`ika-tunnel-test.queloud.net`）で `/health`、ストリーミング、WAF を確かめた
- 11-21: 確認用ホスト名で Mastodon が 403 を返した原因を調べ、トンネルの Host 書き換えをやめた（#13。
  下の「Host ヘッダー」）
- 11-21: 本体の A レコードを Terraform に取り込み、TTL を 60 秒に下げた（#14）。SOA の変更は
  できなかったので取り下げた（#16。下の「DNS の切り替え」）
- 11-22 11:41: 本体の DNS をトンネルを指す CNAME に切り替えた（#17）
- 11-22 昼: nginx への接続が止まったのを確かめて、nginx を止め、80 / 443 を閉じた
- 11-22: 移行のためだけの設定と手順書を消した（この文書を追加した PR）

PR はすべて koba-lab/ikatodon-web のもの。

## 判断したこと

### Host ヘッダー

最初は、確認用ホスト名でも Mastodon に届くよう、トンネルの `httpHostHeader` で Host を
`ika.queloud.net` に書き換えていた。しかし cloudflared は、書き換え前の Host を `X-Forwarded-Host` に
入れて送る（cloudflared 2026.10.7 の `ingress/origin_proxy.go`）。Rails は `X-Forwarded-Host` を
`request.host` として扱うので、書き換えは効かず、Mastodon の Host チェック
（`config/initializers/1_hosts.rb`）で 403 になった。

本体はクライアントが送った Host のまま届けば足りるので、書き換えをやめた。確認用ホスト名では
Host チェックの対象外の `/health` だけを確かめ、本体の受け付けは、各 Web サーバー上から
切り替え後と同じヘッダーを付けて `localhost:3000` に送って確かめた（2 台とも 200）。

### クライアント IP

Mastodon は利用者の IP を `X-Forwarded-For` から取る。Cloudflare は右端に接続元の IP を足し、
Rails は右から信頼するプロキシ（ループバックとプライベートアドレス）を飛ばして最初の IP を使う。
cloudflared は `localhost` から接続するので、設定の変更なしで利用者の IP が取れる見込みだった。
本番の `.env.production` に `TRUSTED_PROXY_IP` がないことも確かめた。

切り替え後、`/cdn-cgi/trace` の `ip=` と `/auth/edit` のセッションの IP が一致することを確かめた。
cloudflared を更新したときの確認手順は [setup.md](setup.md) の「クライアント IP の確認」。

### DNS の切り替え

- 本体の A レコード（管理画面で作ったもの）を Terraform に取り込み、変数ひとつで A レコードと
  CNAME を切り替えられるようにした。切り戻しの PR をすぐ出せるようにするため
- Web サーバーの IP は公開リポジトリに書けないので、Secret から渡した
- A レコードと CNAME は同じ名前に共存できないので、apply は「消してから作る」順になり、1 秒前後
  レコードが無くなる。その瞬間に引いたリゾルバーは「存在しない」を SOA の Minimum TTL（1800 秒）の
  間キャッシュする。SOA を変えて短くしようとしたが、このゾーンでは変更できなかった（API が
  `Custom SOA records are not available to this account or zone` を返した）。リスクを受け入れ、
  利用者の少ない時間に切り替えた
- Google Search Console のサイト確認用 TXT レコードは、Proxied の CNAME と同じ名前でも引けることを
  確認用ホスト名で確かめてから切り替えた

### API 登録の遮断のレスポンス

nginx では JSON のエラーメッセージを返していたが、Cloudflare の WAF で独自のレスポンスを返すには
Pro プラン以上が要る。Cloudflare 標準の 403 ページのままにした。

## 切り替え当日の確認結果

- 2 台の Web サーバーから本体へ: HTTP/2 で 200（HTTP/2 を無効にした nginx ではなく Cloudflare を経由）
- テキストと画像の投稿（PC とスマホアプリ）: 成功
- ストリーミング: スマホアプリからの投稿が、PC のタイムラインにリロードなしで出た
- クライアント IP: 一致
- 連合: 2 台とも `/inbox` への POST が 202 で受け付けられている

nginx へのアクセスは、切り替え前は 10 分あたり 1000〜1500 件あったが、11:50 台には 2 台で 29 件と
18 件になった。`/inbox`（連合の配送）は 0 件だった。残りはクローラー、IP を直接叩くスキャナー、
開きっぱなしのブラウザのタブだったので、ここで nginx を止めた。

## サーバー側で行った変更

このリポジトリの外で、2 台の Web サーバーと ConoHa に対して行ったこと。

- nginx を停止し、自動起動を無効にした（`systemctl disable --now nginx`）
- Let's Encrypt の証明書の更新を止めた
  - `certbot.timer` を無効にした
  - ユーザーの crontab の `certbot renew && service nginx restart` の行をコメントアウトした
    （`service nginx restart` は無効にしたサービスでも起動するため）
  - `/etc/cron.d/certbot` はそのまま（systemd の環境では何もしない作りになっている）
- ConoHa の接続許可ポートから Web（20/21/80/443）を外し、SSH だけにした
- Docker の自動起動が有効なこと（`systemctl is-enabled docker`）を確かめた。cloudflared は
  `restart: always` なので、サーバーを再起動しても上がる

## 移行のあとで消したもの

移行と切り戻しのためだけに用意していたもの。nginx を止めた時点で使わなくなった。

- 確認用ホスト名 `ika-tunnel-test.queloud.net`（DNS レコード、トンネルの ingress、ルールの対象）
- 本体の A レコードと CNAME を切り替える変数 `ika_via_tunnel` と、A レコードの定義
- Web サーバーの IP を渡す変数 `web_ips` と、GitHub Actions の Secret `WEB_IPS`
- 切り替えの手順書 `docs/cutover.md`（切り替えと切り戻しの手順。確認用ホスト名を使った動作確認は
  本体に向けて、クライアント IP の確認は [setup.md](setup.md) に移した）

nginx に戻すことになった場合は、この文書の手前の状態（#17 のマージ時点）の `docs/cutover.md` と
`cloudflare/dns.tf` が参考になる。nginx の起動、証明書の取り直し、80 / 443 の開放も要る。

## 残っていること

- koba-lab の Organization 設定で、パッケージを Public で作れないようにする
  （Settings → Packages → Package creation）
- `files-ika.queloud.net` 用に管理画面で作ったルール（URL Rewrite、Response Header Transform）の
  Terraform への取り込み
- GitHub Actions の Node 20 に関する警告（`hashicorp/setup-terraform@v3` など）
- `tootctl media remove` の cron が 2 台の両方にある。DB とストレージは共有なので、1 台で足りる
- koba-lab/mastodon の `ikatodon/docs/infrastructure.md` の nginx に関する記述の更新
