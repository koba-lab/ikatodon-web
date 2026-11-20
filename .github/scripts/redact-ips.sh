#!/usr/bin/env bash
# WEB_IPS（カンマ区切り）に入っている IP アドレスを、ファイルの中で *** に置き換える。
#
# 使い方: redact-ips.sh <ファイル>
#
# Terraform は sensitive な変数を (sensitive value) と表示するので、通常は何も置き換わらない。
# 公開リポジトリなので、万一 IP が出力に混ざっても PR コメントやログに載らないようにする保険。
# GitHub の Secret のマスクは WEB_IPS の文字列全体にしか効かず、個々の IP は隠れない。

set -euo pipefail

file=$1

[ -n "${WEB_IPS:-}" ] || exit 0

tr ',' '\n' <<<"$WEB_IPS" | while IFS= read -r ip; do
  ip=$(printf '%s' "$ip" | tr -d '[:space:]')
  [ -n "$ip" ] || continue
  # 正規表現として扱われないよう、ドットをエスケープする
  pattern=$(printf '%s' "$ip" | sed 's/[.[\*^$/]/\\&/g')
  sed -i "s/${pattern}/***/g" "$file"
done
