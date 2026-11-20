# 本番の切り替え

`ika.queloud.net` を、DNS ラウンドロビン（各 Web サーバーの nginx へ直接つなぐ）から
Cloudflare Tunnel 経由に切り替える手順です。[setup.md](setup.md) を終えてから行います。

この文書は叩き台です。下の「切り替え前に決めること」が片付いてから、手順を確定させます。

## 切り替え前に決めること

- [ ] **メンテナンスモード**: いまは nginx が `/var/www/html/maintenance.html` の有無で 503 を
      返し、許可 IP だけ素通しにしている。Cloudflare 側での代わりを決める
      （WAF ルールで許可 IP 以外をブロックする案。許可 IP は Cloudflare の IP リストに置き、
      リポジトリには書かない）
- [ ] **API 登録遮断のレスポンス**: nginx では JSON のエラーメッセージを返していた。Cloudflare の
      ブロックは Cloudflare 標準の 403 ページになる。独自のレスポンスを返せるかはプランによるので確認する
- [x] **Host ヘッダー**: 下の「Mastodon 側の事前確認」で確かめる
- [x] **クライアント IP**: 下の「クライアント IP の仕組み」の通り、設定の変更なしで取れる見込み。
      切り替え前に「Mastodon 側の事前確認」、切り替え後に「クライアント IP の確認」を行う
- [ ] **アップロード上限**: Cloudflare の無料プランはリクエストボディが 100MB まで。
      いまの nginx の `client_max_body_size 80m` より大きいので問題ないはず
- [ ] **Let's Encrypt の更新 cron**: 切り替え後は不要になる。止める時期を決める

## クライアント IP の仕組み

Mastodon（Rails）は利用者の IP を `X-Forwarded-For` から取ります。

- Cloudflare は `X-Forwarded-For` を付けてオリジンに送る。利用者が自分で付けてこなければ
  利用者の IP だけ、付けてきた場合はその右端に Cloudflare に接続してきた IP を足す。つまり
  右端が本物で、それより左は利用者が自由に書ける
  （[Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)）
- Rails は `X-Forwarded-For` を右から見て、信頼するプロキシ（既定ではループバックと
  プライベートアドレス）を飛ばし、最初に出てきた IP を利用者の IP にする（`ActionDispatch::RemoteIp`）
- cloudflared はサーバー上から `localhost:3000` に接続するので、Mastodon から見た接続元は
  信頼するプロキシの範囲に入る（nginx のときと同じ）
- 本番の `.env.production` に `TRUSTED_PROXY_IP` はない（2026-11 に確認）。設定すると信頼する範囲が
  変わるので、設定するときはこの前提を見直す

Cloudflare は `CF-Connecting-IP` を使うよう勧めていますが、Mastodon は読みません（読ませるには
上流のコードの変更が要る）。また Tunnel の FAQ には、Tunnel 経由でも `X-Forwarded-For` が付くとは
明記されていません。そのため、切り替え後と cloudflared の更新後に「クライアント IP の確認」を行います。

## Mastodon 側の事前確認

切り替え後に cloudflared が Mastodon へ送るのと同じ形のリクエストを、各 Web サーバー上から
直接送ります。確かめるのは Cloudflare ではなく、こちらの Mastodon の設定です。

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: ika.queloud.net' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-For: 203.0.113.1' http://localhost:3000/api/v1/instance
```

200 が返れば、Host と `X-Forwarded-Proto` を Mastodon が受け付けています。
（403 なら Host、301 なら `X-Forwarded-Proto` の扱いを見直す）

## 手順（案）

1. `ika.queloud.net` の DNS の TTL を短くしておく（前日まで）
2. `cloudflare/dns.tf` に `ika.queloud.net` の CNAME（トンネル向け、proxied）を追加する PR を作る。
   いまの A レコード 2 つは、管理画面で作ったものなら Terraform に import するか、
   apply の直前に手で消す
3. マージして apply する。これで新しい接続は Cloudflare → トンネル → 各 Web サーバーへ流れる
4. 確認
   - トップページ、ログイン、投稿、メディアのアップロード
   - ストリーミング（タイムラインがリアルタイムに更新されるか）
   - 連合（他サーバーからのフォローやリプライが届くか）
   - クライアント IP（下の「クライアント IP の確認」）
5. 問題がなくても、**切り替え直前の A レコードの TTL 以上の時間**が経つまでは nginx と
   80 / 443 を残しておく。切り替え直前に DNS を引いた利用者や連合先は、TTL が切れるまで
   古い IP に接続してくる
6. TTL 以上の時間が経ったら、各 Web サーバーで nginx を止め、80 / 443 を閉じる

## クライアント IP の確認

切り替え後と、cloudflared（トンネルのイメージ）を更新した後に行います。

1. 自分のアカウントでログインし直す
2. `https://ika.queloud.net/auth/edit`（ユーザー設定 → アカウント → セキュリティ）の
   「セッション」で、現在のセッションに自分の回線の IP が出ているかを見る
3. `127.0.0.1`、`172.` で始まるアドレス、Cloudflare の IP になっていたら、利用者の IP が取れて
   いない。すぐに切り戻すか、原因を調べる

## 切り戻し

nginx を止めるまでは、DNS を元の A レコード 2 つに戻せば元の経路に戻ります。
nginx は切り替えの確認が済むまで止めないでください。
