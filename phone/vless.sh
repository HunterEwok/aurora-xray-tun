#!/bin/sh
# VLESS для всего телефона: Xray-core со своим TUN (xtun0).
# Запуск от root:  devel-su sh vless.sh start | stop | status | log
# (sh нужен потому, что /home смонтирована с noexec.)
#
# Собственное соединение Xray с сервером идёт мимо туннеля, маршрутом /32 через шлюз
# Wi-Fi или мобильной сети: без него трафик Xray уходил бы обратно в TUN по кругу.
# Адрес сервера берётся из публичного DNS через HTTPS и прописывается в конфиг.
D=$(cd "$(dirname "$0")" && pwd)
CONF=$D/xray.json
RUN=/run/aurora-xray-tun
BIN=/usr/bin/io.github.hunterewok.XrayTun

server() { sed -n 's/.*"address": "\([^"]*\)".*/\1/p' "$CONF" | head -1; }
resolve() { # имя → IPv4: DoH Cloudflare, потом Google, потом системный DNS
    case $1 in *[!0-9.]*) ;; *) echo "$1"; return ;; esac
    for u in "https://1.1.1.1/dns-query?name=$1&type=A" "https://8.8.8.8/resolve?name=$1&type=A"; do
        ip=$(curl -s --max-time 8 -H 'accept: application/dns-json' "$u" |
            grep -o '"data": *"[0-9.]*"' | tail -1 | grep -o '[0-9.]*[0-9]')
        [ -n "$ip" ] && { echo "$ip"; return; }
    done
    getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}'
}
running() { [ -f $RUN.pid ] && kill -0 "$(cat $RUN.pid)" 2>/dev/null; }

case "$1" in
start)
    [ "$(id -u)" = 0 ] || { echo "нужен root: devel-su sh $0 start"; exit 1; }
    [ -x $BIN ] || { echo "пакет не установлен: нет $BIN"; exit 1; }
    running && { echo "уже запущен"; exit 0; }
    H=$(server); IP=$(resolve "$H")
    [ -n "$IP" ] || { echo "не удалось узнать адрес $H"; exit 1; }
    set -- $(ip route show default | sed -n 's/^default via \([0-9.]*\) dev \([^ ]*\).*/\1 \2/p' | head -1)
    [ -n "${1:-}" ] || { echo "нет маршрута по умолчанию: включён ли Wi-Fi или мобильный интернет?"; exit 1; }
    ip route replace "$IP/32" via "$1" dev "$2"
    echo "$IP" > $RUN.ip
    sed "s/\"$H\": \"[0-9.]*\"/\"$H\": \"$IP\"/" "$CONF" > $RUN.json
    $BIN run -c $RUN.json > $RUN.log 2>&1 &
    echo $! > $RUN.pid
    sleep 3
    if running; then echo "запущен: $H = $IP через $1 ($2)"
    else echo "Xray завершился:"; tail -20 $RUN.log; sh "$0" stop >/dev/null; exit 1; fi
    ;;
stop)
    [ -f $RUN.pid ] && kill "$(cat $RUN.pid)" 2>/dev/null
    [ -f $RUN.ip ] && ip route del "$(cat $RUN.ip)/32" 2>/dev/null
    rm -f $RUN.pid $RUN.ip $RUN.json
    echo "остановлен"
    ;;
status)
    if running; then echo "работает, сервер $(cat $RUN.ip)"; else echo "не запущен"; fi
    ;;
log) tail -30 $RUN.log 2>/dev/null ;;
*) echo "запуск: devel-su sh $0 start|stop|status|log"; exit 2 ;;
esac
