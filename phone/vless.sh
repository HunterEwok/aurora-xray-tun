#!/bin/sh
# VLESS для всего телефона: Xray-core со своим TUN (xtun0).
# Запуск от root:  devel-su sh vless.sh start | stop | status | log | watch | unwatch
# (sh нужен потому, что /home смонтирована с noexec.)
#
# watch запускает сторожа: он работает от root в фоне и включает туннель, пока рядом
# со скриптом есть файл on, и выключает, когда файла нет. Создавать и удалять этот файл
# может обычный пользователь, поэтому on.sh и off.sh обходятся без пароля. Ещё сторож
# перезапускает туннель при смене сети (Wi-Fi ↔ мобильная) и если Xray упал.
#
# Собственное соединение Xray с сервером идёт мимо туннеля, маршрутом /32 через шлюз
# Wi-Fi или мобильной сети: без него трафик Xray уходил бы обратно в TUN по кругу.
# Адрес сервера берётся из публичного DNS через HTTPS и прописывается в конфиг.
# Пути: конфиг и файл-флаг лежат рядом со скриптом (~/xray-tun), служебные файлы
# работающего туннеля — в /run (очищается при перезагрузке):
#   .pid  PID Xray, .ip  адрес сервера, .gw  шлюз и интерфейс, .json  конфиг с адресом,
#   .log  журнал Xray, .watch  PID сторожа, .state  on/off для on.sh и off.sh,
#   .watch.log  журнал сторожа. BIN заменяет setup.sh на путь из своего APP_ID.
D=$(cd "$(dirname "$0")" && pwd)
CONF=$D/xray.json
FLAG=$D/on
RUN=/run/aurora-xray-tun
BIN=/usr/bin/local.xraytun.XrayTun

# Имя сервера из конфига (первое поле "address").
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
# alive <файл с PID>: жив ли процесс; running: работает ли Xray.
alive() { [ -f "$1" ] && [ -d "/proc/$(cat "$1")" ]; }
running() { alive $RUN.pid; }
# Шлюз и интерфейс маршрута по умолчанию (Wi-Fi или мобильная сеть): "адрес интерфейс".
gateway() { ip route show default | sed -n 's/^default via \([0-9.]*\) dev \([^ ]*\).*/\1 \2/p' | head -1; }
need_root() { [ "$(id -u)" = 0 ] || { echo "нужен root: devel-su sh $0 $1"; exit 1; }; }

# Запуск: узнать адрес сервера, проложить к нему маршрут /32 мимо туннеля, подставить
# адрес в конфиг (dns.hosts) и запустить Xray. Xray сам поднимает xtun0 и маршруты.
do_start() {
    [ -x $BIN ] || { echo "пакет не установлен: нет $BIN"; return 1; }
    running && { echo "уже запущен"; return 0; }
    H=$(server); IP=$(resolve "$H")
    [ -n "$IP" ] || { echo "не удалось узнать адрес $H"; return 1; }
    GW=$(gateway)
    [ -n "$GW" ] || { echo "нет маршрута по умолчанию: включён ли Wi-Fi или мобильный интернет?"; return 1; }
    set -- $GW
    ip route replace "$IP/32" via "$1" dev "$2"
    echo "$IP" > $RUN.ip
    echo "$GW" > $RUN.gw
    sed "s/\"$H\": \"[0-9.]*\"/\"$H\": \"$IP\"/" "$CONF" > $RUN.json
    $BIN run -c $RUN.json > $RUN.log 2>&1 &
    echo $! > $RUN.pid
    sleep 3
    if running; then echo "запущен: $H = $IP через $1 ($2)"
    else echo "Xray завершился:"; tail -20 $RUN.log; do_stop >/dev/null; return 1; fi
}
# Остановка: Xray при выходе сам убирает xtun0; маршрут /32 убираем мы.
do_stop() {
    [ -f $RUN.pid ] && kill "$(cat $RUN.pid)" 2>/dev/null
    [ -f $RUN.ip ] && ip route del "$(cat $RUN.ip)/32" 2>/dev/null
    rm -f $RUN.pid $RUN.ip $RUN.gw $RUN.json
    echo "остановлен"
}
watch_loop() { # раз в 3 секунды сверяет туннель с файлом on
    trap '' HUP
    echo $$ > $RUN.watch
    trap 'do_stop; rm -f $RUN.watch $RUN.state; exit 0' TERM INT
    fails=0
    while :; do
        if [ -f "$FLAG" ]; then
            if running && [ "$(gateway)" != "$(cat $RUN.gw 2>/dev/null)" ]; then
                echo "$(date '+%F %T') сеть сменилась, перезапускаю"; do_stop
            fi
            if ! running; then
                # После неудачи ждём дольше, чтобы не дёргать сеть каждые 3 секунды.
                if [ $fails -eq 0 ] || [ $((fails % 10)) -eq 0 ]; then
                    echo "$(date '+%F %T') включаю"
                    if do_start; then fails=0; else fails=$((fails + 1)); fi
                else fails=$((fails + 1)); fi
            fi
        elif running; then
            echo "$(date '+%F %T') выключаю"; do_stop; fails=0
        fi
        if running; then echo on > $RUN.state; else echo off > $RUN.state; fi
        sleep 3
    done
}

# Команды. watch запускает сторожа в фоне (setsid отвязывает его от SSH и терминала),
# unwatch останавливает сторожа и туннель.
case "$1" in
start) need_root start; do_start ;;
stop) need_root stop; do_stop ;;
status)
    if running; then echo "работает, сервер $(cat $RUN.ip)"; else echo "не запущен"; fi
    if alive $RUN.watch; then echo "сторож работает"; fi
    ;;
log) tail -30 $RUN.log 2>/dev/null; tail -5 $RUN.watch.log 2>/dev/null ;;
watch)
    need_root watch
    alive $RUN.watch && { echo "сторож уже работает"; exit 0; }
    if command -v setsid >/dev/null; then setsid sh "$0" _loop </dev/null >>$RUN.watch.log 2>&1 &
    else nohup sh "$0" _loop </dev/null >>$RUN.watch.log 2>&1 & fi
    sleep 1
    alive $RUN.watch || { echo "сторож не запустился:"; tail -5 $RUN.watch.log; exit 1; }
    echo "сторож запущен: включение и выключение теперь без пароля"
    ;;
unwatch)
    need_root unwatch
    if alive $RUN.watch; then
        kill "$(cat $RUN.watch)"
        i=0; while alive $RUN.watch && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
    fi
    do_stop >/dev/null
    rm -f $RUN.watch $RUN.state
    echo "сторож остановлен, туннель выключен"
    ;;
_loop) watch_loop ;;
*) echo "запуск: devel-su sh $0 start|stop|status|log|watch|unwatch"; exit 2 ;;
esac
