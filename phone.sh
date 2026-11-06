#!/bin/sh
# Ставит всё на телефон по SSH и управляет туннелем.
#   ./phone.sh install   берёт пакет с Xray (собранный ./build.sh в out/, из архива
#                        релиза в rpm/ или скачивает из последнего релиза на GitHub),
#                        копирует его и
#                        out/ на телефон, ставит пакет, запускает сторожа (пароль root
#                        нужен здесь) и проверяет
#   ./phone.sh start | stop | status | log
#   ./phone.sh check     показывает, с какого IP телефон выходит в интернет
# Телефон: PHONE=defaultuser@адрес (по умолчанию defaultuser@192.168.2.15, это USB).
# Пароль devel-su (его задают в режиме разработчика) спрашивает только install.
set -eu
cd "$(dirname "$0")"
PHONE=${PHONE:-defaultuser@192.168.2.15}
DIR=xray-tun
REPO=${REPO:-HunterEwok/aurora-xray-tun}
# Одно SSH-соединение на все команды: пароль спрашивается один раз.
SSH_OPTS="-o ControlMaster=auto -o ControlPath=${TMPDIR:-/tmp}/aurora-xray-tun-%r@%h -o ControlPersist=120"

die() { echo "phone.sh: $*" >&2; exit 1; }
on_phone() { ssh $SSH_OPTS "$PHONE" "$@"; }
as_root() { ssh -t $SSH_OPTS "$PHONE" "devel-su sh \$HOME/$DIR/vless.sh $1"; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# Пакет под архитектуру телефона: свой из out/ или готовый из релиза.
package() {
    arch=$(on_phone "rpm -q --qf '%{ARCH}' glibc") || die "не удалось подключиться к $PHONE"
    case $arch in armv7hl|aarch64) ;; *) die "неизвестная архитектура телефона: $arch" ;; esac
    rpm=$(ls out/*.$arch.rpm 2>/dev/null | head -1)
    if [ -n "$rpm" ]; then echo "беру свой пакет $rpm" >&2; echo "$rpm"; return; fi
    # Архив релиза приносит пакеты с собой в rpm/.
    if [ -f rpm/xray-tun.$arch.rpm ]; then
        want=$(awk -v f="xray-tun.$arch.rpm" '$2 == f {print $1}' rpm/SHA256SUMS 2>/dev/null)
        [ -n "$want" ] && [ "$(sha256 rpm/xray-tun.$arch.rpm)" = "$want" ] \
            || die "контрольная сумма rpm/xray-tun.$arch.rpm не совпала с rpm/SHA256SUMS"
        echo "беру пакет из архива: rpm/xray-tun.$arch.rpm" >&2; echo rpm/xray-tun.$arch.rpm; return
    fi
    url=https://github.com/$REPO/releases/latest/download
    mkdir -p out/release
    echo "скачиваю xray-tun.$arch.rpm из последнего релиза $REPO" >&2
    curl -fsSL "$url/xray-tun.$arch.rpm" -o out/release/xray-tun.$arch.rpm \
        && curl -fsSL "$url/SHA256SUMS" -o out/release/SHA256SUMS \
        || die "не удалось скачать релиз; можно собрать пакет самому: ARCH=$arch ./build.sh"
    want=$(awk -v f="xray-tun.$arch.rpm" '$2 == f {print $1}' out/release/SHA256SUMS)
    [ -n "$want" ] && [ "$(sha256 out/release/xray-tun.$arch.rpm)" = "$want" ] \
        || die "контрольная сумма скачанного пакета не совпала с SHA256SUMS"
    echo out/release/xray-tun.$arch.rpm
}

check() {
    server=$(sed -n 's/.*"address": "\([^"]*\)".*/\1/p' out/xray.json | head -1)
    ip=$(on_phone "curl -4 -s --max-time 10 https://ifconfig.me" || true)
    echo "телефон выходит в интернет с адреса: ${ip:-нет ответа}"
    echo "сервер из ссылки: $server"
    echo "Если адреса совпадают (или это адрес выхода вашего сервера), туннель работает."
}

case "${1:-}" in
install)
    [ -f out/xray.json ] && [ -f out/vless.sh ] || die "нет конфига: сначала ./config.sh 'vless://...'"
    rpm=$(package)
    on_phone "mkdir -p $DIR"
    scp $SSH_OPTS "$rpm" out/xray.json out/vless.sh "$PHONE:$DIR/"
    # Короткие on.sh и off.sh кладутся прямо в домашнюю папку, а в ~/.bashrc
    # добавляются команды on и off (один раз, блок помечен).
    scp $SSH_OPTS phone/on.sh phone/off.sh "$PHONE:"
    on_phone "grep -q '# aurora-xray-tun' ~/.bashrc 2>/dev/null || printf '%s\\n' \
        '# aurora-xray-tun: on / off включают и выключают VLESS' \
        'alias on=\"sh ~/on.sh\"' 'alias off=\"sh ~/off.sh\"' >> ~/.bashrc"
    echo "ставлю пакет $(basename "$rpm")"
    on_phone "gdbus call --system --dest ru.omp.APM --object-path /ru/omp/APM \
        --method ru.omp.APM.Install \"\$HOME/$DIR/$(basename "$rpm")\" '{}'"
    sleep 5
    # Сторож от root: пароль root спрашивается здесь, дальше on и off без пароля.
    on_phone "touch $DIR/on"
    as_root watch
    sleep 8
    check
    ;;
start) ssh -t $SSH_OPTS "$PHONE" "sh ~/on.sh" ;;
stop) ssh -t $SSH_OPTS "$PHONE" "sh ~/off.sh" ;;
status|log) on_phone "sh $DIR/vless.sh $1" ;;
check) check ;;
*) echo "запуск: ./phone.sh install|start|stop|status|log|check"; exit 2 ;;
esac
