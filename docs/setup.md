# 初期準備

トンネルを作り、確認用ホスト名（`ika-tunnel-test.queloud.net`）でトンネル経由の動作を
確かめるところまでの手順です。本体（`ika.queloud.net`）はこの手順では切り替えません。
切り替えは [cutover.md](cutover.md) を参照してください。

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

2 つ作ります。どちらも対象ゾーンは `queloud.net` だけに絞ってください。

| 用途     | 権限                                                                                                                 | 登録先                                                      |
| -------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| apply 用 | Account: Cloudflare Tunnel 編集 / Zone: DNS 編集、Zone WAF 編集、Single Redirect 編集、Transform Rules 編集          | Environment `production` の Secret `CLOUDFLARE_API_TOKEN`   |
| plan 用  | 上と同じ項目の読み取り                                                                                               | リポジトリ Secret `CLOUDFLARE_API_TOKEN_READ`               |

権限の名前は Cloudflare の管理画面で変わることがあります。plan / apply で権限不足のエラーが出たら、
エラーに出た権限を足してください。

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

この PR をマージすると、`Terraform (cloudflare)` ワークフローが plan → apply を実行します。
apply の前に Environment `production` の承認を求められます。

## 6. トンネルのイメージ

1. 5 のマージで `Tunnel image` ワークフローも動きます（`Dockerfile` が変わるため）。
   動かなかった場合は手で実行する（Actions → Tunnel image → Run workflow）
2. 初回はパッケージを作るだけで、わざと失敗します（トークンは入っていません）。
   apply より先に動いても、この段階ではトンネルを参照しないので問題ありません
3. GitHub の Packages で `ikatodon-tunnel` を開き、次を確認する
   - Visibility が **Private** であること（Public なら Private に変更する）
   - Manage Actions access に `ikatodon-web` リポジトリが Write で入っていること
4. apply が終わってから、もう一度ワークフローを実行する。今度はトークン入りのイメージが push されます

> [!WARNING]
> トークン入りのイメージが一度でも Public になった場合は、トンネルの secret を変えてください。
> `cloudflare/tunnel.tf` の `random_bytes.tunnel_secret` を作り直し（`terraform apply -replace`）、
> `Tunnel image` を再実行して、各 Web サーバーで pull し直します。

## 7. Web サーバーで起動する（2 台とも）

ghcr への `docker login` は Mastodon のイメージを pull するために済んでいる前提です。

```bash
git clone https://github.com/koba-lab/ikatodon-web ~/ikatodon-web
```

```bash
cd ~/ikatodon-web && docker compose pull && docker compose up -d
```

Cloudflare の管理画面（Zero Trust → Networks → Tunnels → `ikatodon-web`）で、コネクタが 2 つ
接続されていることを確認します。

## 8. 動作確認

確認用ホスト名でトンネル経由のアクセスを確かめます。

```bash
curl -sS https://ika-tunnel-test.queloud.net/health
```

```bash
curl -sS https://ika-tunnel-test.queloud.net/api/v1/streaming/health
```

どちらも `OK` が返れば成功です。

`POST /api/v1/accounts` が遮断されることも確認します（403 が返れば成功）。

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://ika-tunnel-test.queloud.net/api/v1/accounts
```

## イメージの更新

`Dockerfile` を変えて `main` にマージすると `Tunnel image` が走ります。その後、各 Web サーバーで:

```bash
cd ~/ikatodon-web && git pull && docker compose pull && docker compose up -d
```
