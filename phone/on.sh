#!/bin/sh
# Включить VLESS: on (или sh ~/on.sh).
# Пароль root нужен, только если сторож ещё не запущен (первый раз после включения
# телефона); дальше on и off работают без пароля.
D=$HOME/xray-tun
RUN=/run/aurora-xray-tun
touch "$D/on"
if ! { [ -f $RUN.watch ] && [ -d "/proc/$(cat $RUN.watch)" ]; }; then
    echo "Сторож не запущен (так бывает после перезагрузки). Пароль root нужен один раз:"
    devel-su sh "$D/vless.sh" watch || exit 1
fi
i=0
while [ $i -lt 20 ]; do
    [ "$(cat $RUN.state 2>/dev/null)" = on ] && { echo "VLESS включён"; exit 0; }
    sleep 1; i=$((i + 1))
done
echo "VLESS пока не включился, сторож пробует дальше. Журнал: tail $RUN.watch.log"
