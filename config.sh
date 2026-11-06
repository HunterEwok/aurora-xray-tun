#!/bin/sh
# Делает из вашей ссылки vless:// конфиг для телефона, в папку out/:
#   out/xray.json   конфиг Xray: TUN для всего телефона
#   out/vless.sh    start / stop / watch на телефоне (его вызывают on.sh и off.sh)
#
# Запуск: ./config.sh 'vless://UUID@host:port?...#имя'
# IPV6=1 ./config.sh '...'  заворачивает в туннель и IPv6.
# Нужен только python3. Пакет с Xray собирать не нужно: phone.sh install скачает
# готовый из релиза на GitHub (или возьмёт собранный ./build.sh из out/).
set -eu
cd "$(dirname "$0")"
APP_ID=${APP_ID:-io.github.hunterewok.XrayTun}
LINK=${1:-}
die() { echo "config.sh: $*" >&2; exit 1; }
case $LINK in vless://*) ;; *) die "запуск: ./config.sh 'vless://...'" ;; esac
command -v python3 >/dev/null || die "не установлен python3"
mkdir -p out
V6=; [ "${IPV6:-0}" = 1 ] && V6=--ipv6
python3 vless2xray.py $V6 "$LINK" > out/xray.json.tmp && mv out/xray.json.tmp out/xray.json
sed "s|^BIN=.*|BIN=/usr/bin/$APP_ID|" phone/vless.sh > out/vless.sh
echo "готовы out/xray.json и out/vless.sh (в xray.json ваш UUID, не публикуйте его)"
echo "Дальше: ./phone.sh install"
