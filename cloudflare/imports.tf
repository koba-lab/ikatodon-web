# 管理画面で作られていた本体の A レコードを Terraform に取り込む。
# apply で取り込みが済んだら、このファイルは消してよい（残っていても何もしない）。
#
# 番号は WEB_IPS の並び順と対応させる。食い違うと plan にレコードの中身（content）の
# 変更が出るので、その場合は WEB_IPS の順番を入れ替える。

import {
  to = cloudflare_dns_record.direct[0]
  id = "${var.cloudflare_zone_id}/3e5991f709b177c60a3c2ab4cf2e1930"
}

import {
  to = cloudflare_dns_record.direct[1]
  id = "${var.cloudflare_zone_id}/1db2f68e2f97c8148a7ab75f75e48ae6"
}
