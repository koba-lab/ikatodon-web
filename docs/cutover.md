# 本番の切り替え

`ika.queloud.net` を、DNS ラウンドロビン（各 Web サーバーの nginx へ直接つなぐ）から
Cloudflare Tunnel 経由に切り替える手順です。[setup.md](setup.md) を終えてから行います。

この文書は叩き台です。下の「切り替え前に決めること」が片付いてから、手順を確定させます。

## 切り替え前に決めること

- [x] **API 登録遮断のレスポンス**: Cloudflare 標準の 403 ページのままにする（nginx では JSON の
      エラーメッセージを返していた。独自のレスポンスは Pro プラン以上が必要）
- [x] **Host ヘッダー**: 下の「Mastodon 側の事前確認」で確かめる
- [x] **クライアント IP**: 下の「クライアント IP の仕組み」の通り、設定の変更なしで取れる見込み。
      切り替え前に「Mastodon 側の事前確認」、切り替え後に「クライアント IP の確認」を行う
- [x] **Let's Encrypt の更新 cron**: nginx を止めるときに止める（それまでは切り戻しに必要）
- [x] **レコードが無くなる数秒間**: 受け入れる。利用者の少ない時間帯に切り替える（下の「本体の DNS の管理」）
- [x] **Google のサイト確認用 TXT レコード**: Proxied の CNAME と同じ名前に置いた TXT も引けることを
      確認用ホスト名で確かめた（2026-11）。切り替え後も `ika.queloud.net` の TXT は残る

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

## 本体の DNS の管理

本体（`ika.queloud.net`）の向け先は、`cloudflare/variables.tf` の `ika_via_tunnel` で切り替えます。

- `false`（今）: Web サーバーの IP を指す A レコード（DNS only、TTL 60 秒）。IP は GitHub Actions の
  Secret `WEB_IPS` から渡す
- `true`: トンネルを指す CNAME（Proxied、TTL は Cloudflare が 300 秒に固定）

A レコードと CNAME は同じ名前に共存できないため、apply は「古いほうを消してから新しいほうを作る」
順で動きます。その間（1 秒前後）はレコードが無く、その瞬間に引いたリゾルバーは「存在しない」という
答えを、ゾーンの SOA の Minimum TTL（1800 秒）の間キャッシュします。このゾーンでは SOA を変更できない
（API が `Custom SOA records are not available to this account or zone` を返す）ので、このリスクは
受け入れ、利用者の少ない時間帯に切り替えと切り戻しを行います。

## 手順（案）

1. **前日まで**
   - `cloudflare/imports.tf` が無いことを確認する（残っていると、切り替えと切り戻しの plan が失敗する）
   - 切り替えの時間を、利用者の少ない時間帯に決める
   - 本体の A レコードの TTL が 60 秒になっていることを確認する（Terraform で管理）
2. **トンネルが動いていることを確かめる**（切り戻しで cloudflared を止めた後の再切り替えでも必ず行う）
   - 2 台とも cloudflared を起動する

     ```bash
     cd ~/ikatodon-web && docker compose pull && docker compose up -d
     ```

   - Cloudflare の管理画面（Networking → Tunnels）で `ikatodon-web` が Healthy、コネクタが 2 つ
   - 確認用ホスト名で疎通を確かめる（[setup.md](setup.md) の「8. 動作確認」。OK / OK / 403）
   - 「Mastodon 側の事前確認」を 2 台とも行い、200 が返ることを確かめる
3. `ika_via_tunnel` の既定値を `true` にする PR を作る。plan が「A レコード 2 つの削除と
   CNAME 1 つの作成」だけであることを確認してマージし、apply を承認する
4. 確認
   - トップページ、ログイン、投稿、メディアのアップロード
   - ストリーミング（タイムラインがリアルタイムに更新されるか）
   - 連合（他サーバーからのフォローやリプライが届くか）
   - クライアント IP（下の「クライアント IP の確認」）
5. 問題がなくても、**切り替え前の A レコードの TTL（60 秒）以上の時間**が経つまでは nginx と
   80 / 443 を残しておく
6. 切り戻す必要がないと判断できたら、各 Web サーバーで nginx を止め、80 / 443 を閉じる。
   Let's Encrypt の更新 cron を止める

## クライアント IP の確認

切り替え後と、cloudflared（トンネルのイメージ）を更新した後に行います。

1. 自分のアカウントでログインし直す
2. `https://ika.queloud.net/auth/edit`（ユーザー設定 → アカウント → セキュリティ）の
   「セッション」で、現在のセッションに自分の回線の IP が出ているかを見る
3. `127.0.0.1`、`172.` で始まるアドレス、Cloudflare の IP になっていたら、利用者の IP が取れて
   いない。すぐに切り戻すか、原因を調べる

## 切り戻し

### 切り戻す条件

- クライアント IP の確認で、利用者の IP が取れていない
  （全員が同じ IP に見えるので、アクセス制限が全員まとめてかかり、IP ブロックも効かなくなる）
- 手順 4 の確認のどれかが失敗した

### 前提（nginx を止めるまで守る）

- nginx を止めない。80 / 443 を閉じない
- Let's Encrypt の更新 cron を止めない（証明書が切れていると戻れない）

### 手順

1. `ika_via_tunnel` の既定値を `false` に戻す PR を作り、マージして apply を承認する。
   plan が「CNAME 1 つの削除と A レコードの作成（Web サーバーの台数分）」だけであることを確認する
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

GitHub Actions が動かないなど、1 ができないときだけ、Cloudflare の管理画面で直接戻します
（CNAME を消し、Web サーバーの IP の A レコードを DNS only・TTL 60 秒で作る。コメントは
`cloudflare/dns.tf` の `direct` と同じ文言にする）。この場合は Terraform の state と実際がずれるので、
すぐに `ika_via_tunnel = false` の PR を出し、`cloudflare/imports.tf` を作って新しいレコードの ID を
書いてからマージします。plan は A レコードの取り込みだけになるはずです（コメントや TTL が
`dns.tf` と違っていれば、その更新も出る）。取り込みが済んだら `imports.tf` を消します。

```hcl
import {
  to = cloudflare_dns_record.direct[0]
  id = "${var.cloudflare_zone_id}/<レコード ID>"
}
```

ずれたまま別の apply を走らせると、トンネル経由に戻ってしまいます。
（管理画面で消した CNAME が plan で「既に無い」と扱われるかは未確認。plan の結果を見て判断する）
