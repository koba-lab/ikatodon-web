#!/usr/bin/env bash
# トンネルのイメージのパッケージを確かめる。
#
# 使い方:
#   check-package.sh exists   … このワークフローのトークンでパッケージを読めるか（無ければ失敗）
#   check-package.sh private  … ログインしていない人が pull できないか（できれば失敗）
#
# GitHub の Packages API は GITHUB_TOKEN から Private なパッケージを見られない（404 になる）ため、
# レジストリ（ghcr.io）に直接問い合わせる。

set -euo pipefail

mode=$1
repo="koba-lab/ikatodon-tunnel"
scope="repository:${repo}:pull"

tags_status() {
  local token=$1
  curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list"
}

case "$mode" in
  exists)
    token=$(curl -sf -u "${GITHUB_ACTOR}:${GITHUB_TOKEN}" "https://ghcr.io/token?scope=${scope}&service=ghcr.io" | jq -r '.token // empty' || true)
    if [ -z "$token" ] || [ "$(tags_status "$token")" != "200" ]; then
      echo "::error::パッケージ ${repo} を読めません。パッケージが無いか、Package settings の Manage Actions access に ikatodon-web が入っていません（docs/setup.md の 6）。"
      exit 1
    fi
    echo "パッケージを読めることを確認しました"
    ;;
  private)
    body=$(mktemp)
    code=$(curl -s -o "$body" -w '%{http_code}' "https://ghcr.io/token?scope=${scope}&service=ghcr.io")
    if [ "$code" = "401" ] || [ "$code" = "403" ]; then
      echo "ログインしていない状態では取得できません（Private）"
      exit 0
    fi
    token=$(jq -r '.token // empty' < "$body" || true)
    if [ "$code" = "200" ] && [ -n "$token" ] && [ "$(tags_status "$token")" = "200" ]; then
      echo "::error::パッケージ ${repo} をログインしていない状態で取得できます（Public）。トークン入りのイメージは push しません。Package settings の Change visibility で Private にしてください（docs/setup.md）。"
      exit 1
    fi
    echo "::error::パッケージの公開範囲を判定できませんでした（HTTP ${code}）。安全のため止めます。"
    exit 1
    ;;
  *)
    echo "usage: $0 exists|private" >&2
    exit 2
    ;;
esac
