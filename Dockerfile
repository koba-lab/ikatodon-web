# syntax=docker/dockerfile:1

# トンネルのトークンを焼き込んだ cloudflared イメージ。
# ghcr.io/koba-lab/ikatodon-tunnel として GitHub Actions でビルドする（.github/workflows/tunnel-image.yml）。
#
# このイメージにはトンネルのトークンが入っている。トークンを持っていれば偽のコネクタを立てて
# 本番のトラフィックを受け取れるため、パッケージは必ず Private にしておくこと。
# ビルド時は BuildKit の secret で受け取るので、トークンはビルド引数やイメージの履歴には残らない。

FROM busybox:1.37.0 AS token
RUN --mount=type=secret,id=tunnel_token,required=true \
    cp /run/secrets/tunnel_token /token

FROM cloudflare/cloudflared:2026.10.7
LABEL org.opencontainers.image.source="https://github.com/koba-lab/ikatodon-web"

# 65532 は distroless の nonroot ユーザー。
COPY --from=token --chown=65532:65532 --chmod=0400 /token /etc/cloudflared/token

# ENTRYPOINT は元イメージの ["cloudflared", "--no-autoupdate"]。
CMD ["tunnel", "run", "--token-file", "/etc/cloudflared/token"]
