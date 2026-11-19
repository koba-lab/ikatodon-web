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
- [ ] **クライアント IP**: Mastodon（Rails）が `X-Forwarded-For` から実際のクライアント IP を
      取れているか、確認用ホスト名で確かめる（管理画面のログイン履歴や IP ブロックが正しく動くか）
- [ ] **アップロード上限**: Cloudflare の無料プランはリクエストボディが 100MB まで。
      いまの nginx の `client_max_body_size 80m` より大きいので問題ないはず
- [ ] **Let's Encrypt の更新 cron**: 切り替え後は不要になる。止める時期を決める

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
   - クライアント IP（上の「切り替え前に決めること」）
5. 問題なければ、各 Web サーバーで nginx を止め、80 / 443 を閉じる

## 切り戻し

nginx を止めるまでは、DNS を元の A レコード 2 つに戻せば元の経路に戻ります。
nginx は切り替えの確認が済むまで止めないでください。
