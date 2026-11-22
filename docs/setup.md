# 構築と運用

Cloudflare 側（Terraform）とトンネルのイメージを用意し、Web サーバーで cloudflared を動かすまでの
手順と、運用で使う手順です。nginx からこの構成へ移行したときの経緯は
[2026-11-22-cloudflare-tunnel-migration.md](2026-11-22-cloudflare-tunnel-migration.md) にあります。

## 1. R2（Terraform の state 置き場）

1. Cloudflare の管理画面で R2 を有効にする（無料枠の範囲で使う）
2. バケット `ikatodon-web-tfstate` を作る（公開アクセスは無効のまま）
3. R2 の API トークンを作る
   - 権限: Object Read & Write
   - 対象: `ikatodon-web-tfstate` バケットのみ
4. 表示された Access Key ID / Secret Access Key を GitHub のリポジトリ Secret に登録する
   - `R2_ACCESS_KEY_ID`
   - `R2_SECRET_ACCESS_KEY`

## 2. Cloudflare の API トークン

2 つ作ります。どちらも 1 つのトークンにポリシーを 2 つ作ります（Create Token → Custom token →
Permission policies → Add policy）。

- **ポリシー 1（アカウント単位）**: 対象は Entire Account（またはこのアカウント）
  - Cloudflare One Connector: cloudflared（検索語 `cloudflared`）。見つからなければ
    Cloudflare One Connectors、それも無ければ Argo Tunnel (Legacy)
- **ポリシー 2（ゾーン単位）**: 対象は `queloud.net` だけ
  - Zone（ゾーン情報。apply 用でも読み取りでよい）
  - DNS（本体の CNAME）
  - Zone WAF（API 登録の遮断ルール）
  - Dynamic URL Redirects（`/ikatodon-media/` のリダイレクト）
  - Zone Transform Rules または Transform Rules（`Forwarded` ヘッダーの除去）

| 用途     | 権限                                   | 登録先                                                    |
| -------- | -------------------------------------- | --------------------------------------------------------- |
| apply 用 | 上の項目を Edit（Zone だけ Read）      | Environment `production` の Secret `CLOUDFLARE_API_TOKEN` |
| plan 用  | 上の項目をすべて Read                  | リポジトリ Secret `CLOUDFLARE_API_TOKEN_READ`             |

権限の名前は Cloudflare 公式ドキュメント（API の権限名）に合わせています。管理画面の表示名は
変わることがあるので、見つからないときは括弧内の検索語で探してください。plan / apply で権限不足の
エラーが出たら、エラーに出た権限を足してください。

## 3. GitHub の設定

1. リポジトリ変数（Settings → Secrets and variables → Actions → Variables）
   - `CLOUDFLARE_ACCOUNT_ID`
   - `CLOUDFLARE_ZONE_ID`（`queloud.net` のゾーン ID）
2. Environment `production` を作る
   - Required reviewers: 運営者
   - Deployment branches: `main` のみ

## 4. 既存のルールセットの確認

Cloudflare のルールセット（WAF のカスタムルール、リダイレクト、ヘッダーの変換）は、フェーズごとに
1 ゾーンに 1 つしか作れません。`queloud.net` に管理画面で作ったルールが既にあると、apply が失敗します。

管理画面で次の 3 つにルールがあるか確認してください。

- Security → WAF → Custom rules
- Rules → Redirect Rules
- Rules → Transform Rules → Request Header Transform

既存のルールがある場合は、そのルールを `cloudflare/rules.tf` に書き写してから、ルールセットを
import します（import の PR を別に作る）。

```hcl
import {
  to = cloudflare_ruleset.firewall_custom
  id = "zones/<ゾーン ID>/<ルールセット ID>"
}
```

## 5. apply

`cloudflare/` を変える PR を出すと、`Terraform (cloudflare)` ワークフローが plan を実行し、
結果を PR にコメントします（PR を更新するたびに同じコメントが書き換わります）。

マージすると、次の流れで apply されます。

1. もう一度 plan が走り、結果がマージ元の PR にコメントされる
2. apply が Environment `production` の承認待ちで止まる。PR のコメントにある「実行画面」の
   リンクを開き、**Review deployments** → `production` にチェック → **Approve and deploy**
3. apply が走り、結果（成功 / 失敗と、作成・変更・削除の件数）がマージ元の PR にコメントされる

Environment `production` に Required reviewers が設定されていないと、承認なしで apply されて
しまいます。その場合は plan の時点でワークフローが止まるようにしてあるので、3 の設定を
見直してください。

## 6. トンネルのイメージ

パッケージ `ghcr.io/koba-lab/ikatodon-tunnel` は、ワークフローではなく**手元から**作ります。
公開リポジトリのワークフローが作ったパッケージは、リポジトリの公開範囲を引き継いで Public に
なるためです。手元から作ったパッケージはリポジトリに紐付かず、Private で作られます。

1. 手元（Docker が使える環境）で ghcr にログインする。`gh` を使う場合:

   ```bash
   gh auth refresh -s write:packages
   ```

   ```bash
   gh auth token | docker login ghcr.io -u <GitHub のユーザー名> --password-stdin
   ```

2. トークンを含まないイメージで、パッケージを作る

   ```bash
   docker buildx imagetools create --tag ghcr.io/koba-lab/ikatodon-tunnel:bootstrap cloudflare/cloudflared:2026.10.7
   ```

3. GitHub の Packages で `ikatodon-tunnel` を開き、次を確認する
   - Visibility が **Private** であること
   - Package settings → Manage Actions access に `ikatodon-web` リポジトリを **Write** で追加する
4. Actions → Tunnel image → Run workflow で **visibility_test にチェックを入れて**実行する。
   トークンを含まないイメージを push して、Private のままかを確かめるだけの実行です
5. 4 が成功したら、visibility_test のチェックを外してもう一度実行する。今度はトークン入りの
   イメージが push されます。push の後にも Private のままかを確かめます

パッケージが Public になってしまったら、Package settings → Danger Zone → Change visibility で
Private に戻してから 4 をやり直します（2026-11 に Public から Private へ戻せることを確認済み）。

> [!WARNING]
> トークン入りのイメージが一度でも Public になった場合や、トークンが漏れた疑いがある場合は、
> 下の「トークンが漏れたとき」の手順を実行してください。

## 7. Web サーバーで起動する（2 台とも）

ghcr への `docker login` は Mastodon のイメージを pull するために済んでいる前提です。
Web サーバーは 80 / 443 を開けません（ConoHa の接続許可ポートは SSH だけ）。cloudflared は
Cloudflare へ外向きに接続するだけなので、受け付けるポートは要りません。

```bash
git clone https://github.com/koba-lab/ikatodon-web ~/ikatodon-web
```

```bash
cd ~/ikatodon-web && docker compose pull && docker compose up -d
```

ログに `Registered tunnel connection` が出れば接続できています。

Cloudflare の管理画面（dash.cloudflare.com → アカウント → Networking → Tunnels → `ikatodon-web`）で、
Status が Healthy で、コネクタが 2 つ接続されていることを確認します。

## 8. 動作確認

```bash
curl -sS -o /dev/null -w '%{http_version} %{http_code}\n' https://ika.queloud.net/health
```

```bash
curl -sS https://ika.queloud.net/api/v1/streaming/health
```

`2 200`（または `3 200`）と `OK` が返れば、トンネル経由で web と streaming に届いています。

`POST /api/v1/accounts` が遮断されることも確認します（403 が返れば成功）。

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://ika.queloud.net/api/v1/accounts
```

あわせて下の「クライアント IP の確認」を行います。

## クライアント IP の確認

cloudflared（トンネルのイメージ）を更新した後や、Mastodon の `TRUSTED_PROXY_IP` を変えた後に行います。

1. ブラウザで `https://ika.queloud.net/cdn-cgi/trace` を開き、`ip=` の値を見る（自分の回線の IP）
2. 自分のアカウントでログインし直し、`https://ika.queloud.net/auth/edit`（ユーザー設定 →
   アカウント → セキュリティ）の「セッション」で、現在のセッションの IP が 1 と同じかを見る
3. `127.0.0.1`、`172.` で始まるアドレス、Cloudflare の IP になっていたら、利用者の IP が取れていない。
   全員が同じ IP に見えるため、レート制限が全員まとめてかかり、IP ブロックも効かなくなる。
   直前の変更を戻す

仕組みは次のとおりです。

- Cloudflare は `X-Forwarded-For` の右端に、Cloudflare に接続してきた IP を足してオリジンに送る
  （[Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)）
- Rails（`ActionDispatch::RemoteIp`）は `X-Forwarded-For` を右から見て、信頼するプロキシ（既定では
  ループバックとプライベートアドレス）を飛ばし、最初に出てきた IP を利用者の IP にする
- cloudflared はサーバー上から `localhost:3000` に接続するので、Mastodon から見た接続元は信頼する
  プロキシの範囲に入る。本番の `.env.production` に `TRUSTED_PROXY_IP` はない（2026-11 に確認）

Cloudflare は `CF-Connecting-IP` を勧めていますが、Mastodon は読みません（読ませるには上流の
コードの変更が要る）。Tunnel 経由でも `X-Forwarded-For` が付くことはドキュメントに明記されていない
ため、更新のたびにこの確認を行います。

## トークンが漏れたとき

トークンを持っていれば、偽のコネクタを立てて本番のトラフィックを受け取れます。次の順で対応します。

1. **パッケージが Public になっていたら Private に戻す。** Packages の `ikatodon-tunnel` →
   Package settings → Danger Zone → Change visibility。Private に戻しても、Public だった間に
   取得されたトークンは使えてしまうので、2 以降は必ず行う
2. **トンネルの secret を変える。** `cloudflare/variables.tf` の `tunnel_secret_generation` の
   既定値を 1 増やす PR を作り、マージして apply する
3. **既存の接続を切る。** secret を変えても、古いトークンで接続済みのコネクタは切断されません。
   Cloudflare API で、トンネルの接続をすべて削除します（トークンは Cloudflare Tunnel の編集権限が
   あるもの。アカウント ID とトンネル ID は Terraform の変数・出力で確認する）

   ```bash
   curl -fsS -X DELETE \
     -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
     "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/connections"
   ```

4. **新しいトークンでイメージを作り直す。** `Tunnel image` ワークフローを手で実行する
5. **両方の Web サーバーで入れ替える。**

   ```bash
   cd ~/ikatodon-web && git pull && docker compose pull && docker compose up -d
   ```

6. Cloudflare の管理画面（Networking → Tunnels）で、コネクタが 2 つだけ接続されていることを確認する

## イメージの更新

`Dockerfile` を変えて `main` にマージしたら、Actions → Tunnel image → Run workflow で手動実行します
（トークン入りのイメージを push するので、自動では動きません）。その後、各 Web サーバーで:

```bash
cd ~/ikatodon-web && git pull && docker compose pull && docker compose up -d
```

更新したら、「8. 動作確認」と「クライアント IP の確認」を行います（cloudflared の挙動が変わって、
Mastodon が利用者の IP を取れなくなっていないかを見るため）。
