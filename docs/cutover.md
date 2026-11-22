# 本番の切り替え

`ika.queloud.net` を、DNS ラウンドロビン（各 Web サーバーの nginx へ直接つなぐ）から
Cloudflare Tunnel 経由に切り替える手順です。[setup.md](setup.md) を終えてから行います。

切り替えは `cloudflare/variables.tf` の `ika_via_tunnel` を `true` にする PR のマージで、
切り戻しは `false` に戻す PR のマージで行います（仕組みは下の「DNS の切り替えの仕組み」）。

## 流れ

1. 事前確認（当日、マージの前）
2. 切り替え（PR をマージして apply）
3. 動作確認
4. 問題があれば切り戻し、なければ後日 nginx を止める

## 1. 事前確認

切り替えの時間は、利用者の少ない時間帯にします。切り戻しで cloudflared を止めた後に
もう一度切り替えるときも、この確認からやり直します。

1. 2 台とも cloudflared を最新にして起動する

   ```bash
   cd ~/ikatodon-web && git pull && docker compose pull && docker compose up -d
   ```

2. Cloudflare の管理画面（Networking → Tunnels）で、`ikatodon-web` が Healthy、コネクタが 2 つ
3. 確認用ホスト名で疎通を確かめる（[setup.md](setup.md) の「8. 動作確認」。OK / OK / 403）
4. 2 台とも、Mastodon が切り替え後と同じ形のリクエストを受け付けるかを確かめる。
   cloudflared が Mastodon へ送るのと同じヘッダーを付けて、サーバー上から直接送る

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: ika.queloud.net' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-For: 203.0.113.1' http://localhost:3000/api/v1/instance
   ```

   200 なら成功（403 なら Host、301 なら `X-Forwarded-Proto` の扱いを見直す）

5. `cloudflare/imports.tf` が無いことを確認する（残っていると plan が失敗する）

## 2. 切り替え

1. `ika_via_tunnel` の既定値を `true` にする PR の plan が、次の内容だけであることを確認する
   - 削除: `cloudflare_dns_record.direct`（A レコード、Web サーバーの台数分）
   - 追加: `cloudflare_dns_record.tunnel[0]`（CNAME）
2. マージして apply を承認する

## 3. 動作確認

- トップページ、ログイン、投稿、メディアのアップロード
- ストリーミング（タイムラインがリアルタイムに更新されるか）
- 連合（他サーバーからのフォローやリプライが届くか）
- クライアント IP（下の「クライアント IP の確認」）

どれかが失敗したら「切り戻し」へ進みます。

## 4. nginx を止める

問題がなくても、nginx と 80 / 443、Let's Encrypt の更新 cron は、切り戻す必要がないと判断できるまで
残します（切り戻し先になるため。証明書が切れていると戻れない）。少なくとも切り替え前の A レコードの
TTL（60 秒）が経つまでは必ず残します。

判断できたら、各 Web サーバーで次を行います。

- nginx を止める
- 80 / 443 を閉じる
- Let's Encrypt の更新 cron を止める

## クライアント IP の確認

切り替え後と、cloudflared（トンネルのイメージ）を更新した後に行います。

1. 自分のアカウントでログインし直す
2. `https://ika.queloud.net/auth/edit`（ユーザー設定 → アカウント → セキュリティ）の
   「セッション」で、現在のセッションに自分の回線の IP が出ているかを見る
3. `127.0.0.1`、`172.` で始まるアドレス、Cloudflare の IP になっていたら、利用者の IP が取れて
   いない。切り戻す

利用者の IP が取れないと、全員が同じ IP に見えるため、アクセス制限が全員まとめてかかり、
IP ブロックも効かなくなります。

## 切り戻し

1. `ika_via_tunnel` の既定値を `false` に戻す PR を作る。plan が「CNAME 1 つの削除と
   A レコードの作成（Web サーバーの台数分）」だけであることを確認し、マージして apply を承認する
2. apply が済んだら、**すぐに 2 台とも cloudflared を止める**（トンネル経由で二次被害が出るのを防ぐ）

   ```bash
   cd ~/ikatodon-web && docker compose down
   ```

   CNAME は TTL 300 秒なので、止めてから最大 5 分ほどは、古い答えをキャッシュした利用者に
   Cloudflare のエラー画面が出る。それは受け入れる
3. 戻ったことを確かめる

   ```bash
   curl -sS -o /dev/null -w '%{http_version} %{http_code}\n' https://ika.queloud.net/health
   ```

   `1.1 200` が返れば、nginx（HTTP/2 を無効にした設定）に戻っている。5 分経っても `2` や `3` が
   返る場合は、まだ Cloudflare を経由している

### GitHub Actions が使えないとき

上の 1 ができないときだけ、Cloudflare の管理画面で直接戻します（CNAME を消し、Web サーバーの IP の
A レコードを DNS only・TTL 60 秒で作る。コメントは `cloudflare/dns.tf` の `direct` と同じ文言にする）。
その後は上の 2・3 と同じです。

この場合は Terraform の state と実際がずれるので、すぐに `ika_via_tunnel = false` の PR を出し、
`cloudflare/imports.tf` を作って新しいレコードの ID を書いてからマージします。plan は A レコードの
取り込みだけになるはずです（コメントや TTL が `dns.tf` と違っていれば、その更新も出る）。
取り込みが済んだら `imports.tf` を消します。

```hcl
import {
  to = cloudflare_dns_record.direct[0]
  id = "${var.cloudflare_zone_id}/<レコード ID>"
}
```

ずれたまま別の apply を走らせると、トンネル経由に戻ってしまいます。
（管理画面で消した CNAME が plan で「既に無い」と扱われるかは未確認。plan の結果を見て判断する）

## 背景

### DNS の切り替えの仕組み

- `ika_via_tunnel = false`: Web サーバーの IP を指す A レコード（DNS only、TTL 60 秒）。IP は
  GitHub Actions の Secret `WEB_IPS` から渡す
- `ika_via_tunnel = true`: トンネルを指す CNAME（Proxied、TTL は Cloudflare が 300 秒に固定）

A レコードと CNAME は同じ名前に共存できないため、apply は「古いほうを消してから新しいほうを作る」
順で動きます。その間（1 秒前後）はレコードが無く、その瞬間に引いたリゾルバーは「存在しない」という
答えを、ゾーンの SOA の Minimum TTL（1800 秒）の間キャッシュします。このゾーンでは SOA を変更できない
（API が `Custom SOA records are not available to this account or zone` を返す）ので、このリスクは
受け入れ、利用者の少ない時間帯に切り替えと切り戻しを行います。

Google のサイト確認用 TXT レコードは、切り替え後も `ika.queloud.net` に残ります（Proxied の CNAME と
同じ名前に置いた TXT も引けることを、確認用ホスト名で確かめた。2026-11）。

### クライアント IP の仕組み

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

### API 登録遮断のレスポンス

`POST /api/v1/accounts` の遮断は Cloudflare 標準の 403 ページを返します（nginx では JSON の
エラーメッセージを返していた。独自のレスポンスは Pro プラン以上が必要）。
