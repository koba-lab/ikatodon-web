#!/usr/bin/env bash
# Terraform の plan / apply の結果を、実行のサマリーと PR のコメントに書き出す。
#
# 使い方: tf-report.sh <plan|apply> <終了コード> <出力ファイル> <コメントの識別子>
#
# - サマリー（$GITHUB_STEP_SUMMARY）には毎回書く
# - PR のコメントは識別子ごとに 1 つだけ作り、2 回目以降は上書きする
# - PR 番号は PR_NUMBER、無ければコミットから辿る（main への push はマージ元の PR に書く）
# - EXTRA_NOTE があれば見出しの下に足す
#
# このリポジトリは公開されている。plan / apply の出力は Terraform が秘密情報を
# (sensitive value) に置き換えたものだけで、それ以外の値を足さないこと。

set -euo pipefail

kind=$1
code=$2
out=$3
marker_name=$4

marker="<!-- ikatodon-web:${marker_name} -->"
run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
limit=60000

if [ "$kind" = "plan" ]; then
  summary=$(grep -E '^(Plan:|No changes\.)' "$out" | tail -n 1 || true)
else
  summary=$(grep -E '^Apply complete!' "$out" | tail -n 1 || true)
fi
[ -n "$summary" ] || summary="概要を取得できませんでした。下の出力を確認してください"

if [ "$code" = "0" ]; then
  status="✅ 成功"
else
  status="❌ 失敗（exit ${code}）"
fi

body=$(mktemp)
{
  echo "$marker"
  echo "### Terraform ${kind}（cloudflare）: ${status}"
  echo
  echo "**${summary}**"
  echo
  if [ -n "${EXTRA_NOTE:-}" ]; then
    echo "$EXTRA_NOTE"
    echo
  fi
  echo "<details><summary>出力を見る</summary>"
  echo
  echo '````text'
  head -c "$limit" "$out"
  if [ "$(wc -c < "$out")" -gt "$limit" ]; then
    echo
    echo "...（長いので省略。全文は実行ログを見てください）"
  fi
  echo '````'
  echo
  echo "</details>"
  echo
  echo "[実行ログ](${run_url})"
} > "$body"

cat "$body" >> "$GITHUB_STEP_SUMMARY"

pr="${PR_NUMBER:-}"
if [ -z "$pr" ]; then
  pr=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" --jq '.[0].number // empty' || true)
fi
if [ -z "$pr" ]; then
  echo "対応する PR が見つからないので、コメントは書きません"
  exit 0
fi

comment_id=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${pr}/comments" \
  --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | contains(\"${marker}\"))) | .id" \
  | tail -n 1)

if [ -n "$comment_id" ]; then
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${comment_id}" -F body=@"$body" > /dev/null
else
  gh api "repos/${GITHUB_REPOSITORY}/issues/${pr}/comments" -F body=@"$body" > /dev/null
fi
