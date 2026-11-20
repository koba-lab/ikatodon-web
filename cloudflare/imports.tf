# 管理画面で作られていた本体の A レコードを Terraform に取り込む。
#
# 取り込みの apply が済んだら、次の PR でこのファイルを必ず消す（切り替えの PR より前に）。
# 残っていると、ika_via_tunnel = true で direct が 0 件になったときに取り込み先が無くなり、
# 切り戻しで A レコードを作り直したときには、消えた古い ID を取り込もうとして、plan が失敗する。
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
