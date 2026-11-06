#!/bin/sh
# Выключить VLESS: off (или sh ~/off.sh). Пароль не нужен, если работает сторож.
D=$HOME/xray-tun
RUN=/run/aurora-xray-tun
# Без файла on сторож выключает туннель.
rm -f "$D/on"
# Есть сторож: ждём его. Сторожа нет, а Xray работает: останавливаем сами (нужен root).
if [ -f $RUN.watch ] && [ -d "/proc/$(cat $RUN.watch)" ]; then
    i=0
    while [ $i -lt 10 ]; do
        [ "$(cat $RUN.state 2>/dev/null)" = off ] && { echo "VLESS выключен"; exit 0; }
        sleep 1; i=$((i + 1))
    done
    echo "VLESS ещё не выключился. Журнал: tail $RUN.watch.log"
elif [ -f $RUN.pid ] && [ -d "/proc/$(cat $RUN.pid)" ]; then
    devel-su sh "$D/vless.sh" stop
else
    echo "VLESS уже выключен"
fi
