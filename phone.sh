#!/bin/sh
# Ставит собранное на телефон по SSH и управляет туннелем.
#   ./phone.sh install   копирует out/ на телефон, ставит пакет, запускает и проверяет
#   ./phone.sh start | stop | status | log
#   ./phone.sh check     показывает, с какого IP телефон выходит в интернет
# Телефон: PHONE=defaultuser@адрес (по умолчанию defaultuser@192.168.2.15, это USB).
# Команды root спрашивают пароль devel-su (его задают в режиме разработчика).
set -eu
cd "$(dirname "$0")"
PHONE=${PHONE:-defaultuser@192.168.2.15}
DIR=xray-tun
# Одно SSH-соединение на все команды: пароль спрашивается один раз.
SSH_OPTS="-o ControlMaster=auto -o ControlPath=${TMPDIR:-/tmp}/aurora-xray-tun-%r@%h -o ControlPersist=120"

die() { echo "phone.sh: $*" >&2; exit 1; }
on_phone() { ssh $SSH_OPTS "$PHONE" "$@"; }
as_root() { ssh -t $SSH_OPTS "$PHONE" "devel-su sh \$HOME/$DIR/vless.sh $1"; }

check() {
    server=$(sed -n 's/.*"address": "\([^"]*\)".*/\1/p' out/xray.json | head -1)
    ip=$(on_phone "curl -4 -s --max-time 10 https://ifconfig.me" || true)
    echo "телефон выходит в интернет с адреса: ${ip:-нет ответа}"
    echo "сервер из ссылки: $server"
    echo "Если адреса совпадают (или это адрес выхода вашего сервера), туннель работает."
}

case "${1:-}" in
install)
    rpm=$(ls out/*.rpm 2>/dev/null | head -1)
    [ -n "$rpm" ] || die "нет out/*.rpm: сначала ./build.sh 'vless://...'"
    on_phone "mkdir -p $DIR"
    scp $SSH_OPTS "$rpm" out/xray.json out/vless.sh "$PHONE:$DIR/"
    # Короткие on.sh и off.sh кладутся прямо в домашнюю папку.
    scp $SSH_OPTS phone/on.sh phone/off.sh "$PHONE:"
    echo "ставлю пакет $(basename "$rpm")"
    on_phone "gdbus call --system --dest ru.omp.APM --object-path /ru/omp/APM \
        --method ru.omp.APM.Install \"\$HOME/$DIR/$(basename "$rpm")\" '{}'"
    sleep 5
    as_root start
    check
    ;;
start|stop|status|log) as_root "$1" ;;
check) check ;;
*) echo "запуск: ./phone.sh install|start|stop|status|log|check"; exit 2 ;;
esac
