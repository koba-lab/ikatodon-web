# syntax=docker/dockerfile:1

# トンネルのトークンを焼き込んだ cloudflared イメージ。
# ghcr.io/koba-lab/ikatodon-tunnel として GitHub Actions でビルドする（.github/workflows/tunnel-image.yml）。
#
# このイメージにはトンネルのトークンが入っている。トークンを持っていれば偽のコネクタを立てて
# 本番のトラフィックを受け取れるため、パッケージは必ず Private にしておくこと。
# ビルド時は BuildKit の secret で受け取るので、トークンはビルド引数やイメージの履歴には残らない。

# トークンのファイルとその置き場所を、権限ごとこのステージで用意する。
# COPY --chmod を使うと、自動で作られる親ディレクトリにも同じ権限（0400）が付いて
# 中に入れなくなるため使わない。65532 は元イメージの実行ユーザー（distroless の nonroot）。
FROM busybox:1.38.0 AS token
RUN --mount=type=secret,id=tunnel_token,required=true \
    mkdir -p /out/etc/cloudflared \
    && cp /run/secrets/tunnel_token /out/etc/cloudflared/token \
    && chown -R 65532:65532 /out/etc/cloudflared \
    && chmod 0500 /out/etc/cloudflared \
    && chmod 0400 /out/etc/cloudflared/token

FROM cloudflare/cloudflared:2026.11.1
# org.opencontainers.image.source ラベルは付けない。付けるとパッケージがこの公開リポジトリに
# 紐付き、公開範囲を引き継ぐおそれがある。

COPY --from=token /out/etc/cloudflared /etc/cloudflared

# ENTRYPOINT は元イメージの ["cloudflared"]。イメージの更新で入れ替えるので自動更新は止める。
CMD ["--no-autoupdate", "tunnel", "run", "--token-file", "/etc/cloudflared/token"]
