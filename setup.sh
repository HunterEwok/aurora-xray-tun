#!/bin/sh
# VLESS на телефоне с ОС Аврора, одной командой с компьютера.
#
#   ./setup.sh 'vless://UUID@host:port?...#имя' [адрес телефона]   поставить или заменить ссылку
#   ./setup.sh remove [адрес телефона]                             удалить всё с телефона
#
# Адрес телефона: IP в Wi-Fi (например 192.168.1.50) или имя из ~/.ssh/config. Без него
# берётся 192.168.2.15: так телефон виден по USB. Пользователь по умолчанию defaultuser.
# IPV6=1 заворачивает в туннель и IPv6. Пароль root (devel-su) спрашивается один раз.
# Пакет с Xray берётся собранный ./build.sh из out/, из архива релиза (rpm/) или
# скачивается из последнего релиза на GitHub; SHA-256 сверяется всегда.
set -eu
cd "$(dirname "$0")"
# Настройки: адрес телефона (второй аргумент), имя пакета (как в build.sh), репозиторий
# с релизами и папка на телефоне (~/xray-tun). Голый IP дополняется пользователем.
PHONE=${2:-192.168.2.15}
case $PHONE in *@*) ;; *.*.*.*) PHONE=defaultuser@$PHONE ;; esac
APP_ID=${APP_ID:-local.xraytun.XrayTun}
REPO=${REPO:-HunterEwok/aurora-xray-tun}
DIR=xray-tun
# Одно SSH-соединение на все команды: пароль SSH спрашивается один раз. Сокет лежит
# в /tmp с коротким именем (%C — хэш адреса): путь к сокету не может быть длиннее
# ~100 символов, а $TMPDIR на Маке для этого слишком длинный.
SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/axt-%C -o ControlPersist=120"

die() { echo "setup.sh: $*" >&2; exit 1; }
# on_phone: команда на телефоне; as_root: vless.sh <команда> от root через devel-su
# (-t нужен, чтобы devel-su мог спросить пароль).
on_phone() { ssh $SSH_OPTS "$PHONE" "$@"; }
as_root() {
    echo "Сейчас devel-su спросит пароль суперпользователя (Password:). Это пароль из"
    echo "«Настройки → Для разработчиков», тот же, что для SSH; при вводе он не виден."
    ssh -q -t $SSH_OPTS "$PHONE" "devel-su sh \$HOME/$DIR/vless.sh $1"
}
step() { echo "==> $*"; }  # строка о текущем шаге, чтобы было видно, что скрипт работает
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
apm() { # установщик пакетов Авроры: apm Install <файл> | Remove <пакет> | GetPackage <пакет>
    case $1 in GetPackage) opts= ;; *) opts=" '{}'" ;; esac
    on_phone "gdbus call --system --dest ru.omp.APM --object-path /ru/omp/APM --method ru.omp.APM.$1 \"$2\"$opts"
}

alive() { # работает ли на телефоне сторож (watch) или Xray (pid)
    on_phone "f=/run/aurora-xray-tun.$1; [ -f \$f ] && [ -d /proc/\$(cat \$f) ]"
}

# Пакет под архитектуру телефона, с проверкой SHA-256.
package() {
    arch=$(on_phone "rpm -q --qf '%{ARCH}' glibc") || die "не удалось подключиться к $PHONE"
    case $arch in armv7hl|aarch64) ;; *) die "неизвестная архитектура телефона: $arch" ;; esac
    rpm=$(ls out/*.$arch.rpm 2>/dev/null | head -1)
    if [ -n "$rpm" ]; then echo "беру свой пакет $rpm" >&2; echo "$rpm"; return; fi
    if [ ! -f rpm/xray-tun.$arch.rpm ]; then
        echo "скачиваю xray-tun.$arch.rpm из последнего релиза $REPO" >&2
        url=https://github.com/$REPO/releases/latest/download
        mkdir -p rpm
        curl -fsSL "$url/xray-tun.$arch.rpm" -o rpm/xray-tun.$arch.rpm \
            && curl -fsSL "$url/SHA256SUMS" -o rpm/SHA256SUMS \
            || die "не удалось скачать релиз; можно собрать пакет самому: ARCH=$arch ./build.sh"
    fi
    want=$(awk -v f="xray-tun.$arch.rpm" '$2 == f {print $1}' rpm/SHA256SUMS 2>/dev/null)
    [ -n "$want" ] && [ "$(sha256 rpm/xray-tun.$arch.rpm)" = "$want" ] \
        || die "контрольная сумма rpm/xray-tun.$arch.rpm не совпала с rpm/SHA256SUMS"
    echo rpm/xray-tun.$arch.rpm
}

# Установка или замена ссылки: конфиг из ссылки, файлы на телефон, пакет через
# установщик Авроры, запуск сторожа и туннеля, проверка внешнего адреса.
install() {
    command -v python3 >/dev/null || die "не установлен python3"
    # Конфиг с вашим UUID живёт только во временной папке и на телефоне.
    TMP=$(mktemp -d)
    trap 'rm -r "$TMP"' EXIT
    V6=; [ "${IPV6:-0}" = 1 ] && V6=--ipv6
    step "делаю конфиг из ссылки"
    python3 vless2xray.py $V6 "$1" > "$TMP/xray.json"
    sed "s|^BIN=.*|BIN=/usr/bin/$APP_ID|" phone/vless.sh > "$TMP/vless.sh"
    server=$(sed -n 's/.*"address": "\([^"]*\)".*/\1/p' "$TMP/xray.json" | head -1)

    step "подключаюсь к телефону $PHONE и выбираю пакет"
    rpm=$(package)
    on_phone "mkdir -p $DIR"
    # Пакет около 12 МБ: scp показывает полосу копирования.
    step "копирую на телефон пакет и скрипты"
    scp $SSH_OPTS "$rpm" "$PHONE:$DIR/"
    scp -q $SSH_OPTS "$TMP/xray.json" "$TMP/vless.sh" "$PHONE:$DIR/"
    # Короткие команды: on.sh и off.sh в домашней папке и on / off в ~/.bashrc.
    scp -q $SSH_OPTS phone/on.sh phone/off.sh "$PHONE:"
    on_phone "grep -q '# aurora-xray-tun' ~/.bashrc 2>/dev/null || printf '%s\\n' \
        '# aurora-xray-tun: on / off включают и выключают VLESS' \
        'alias on=\"sh ~/on.sh\"' 'alias off=\"sh ~/off.sh\"' >> ~/.bashrc"
    # Установщик Авроры не ставит пакет поверх той же или более новой версии
    # (DowngradeAttempt), а пакет с другой подписью не обновляет. Поэтому: та же версия
    # уже стоит — ничего не ставим; стоит другая — сначала удаляем её.
    f=\$HOME/$DIR/$(basename "$rpm")
    want=$(on_phone "rpm -qp --qf '%{VERSION}-%{RELEASE}' $f")
    # Версию установленного спрашиваем у самого установщика: rpm -q от пользователя
    # пакетов, поставленных через APM, не видит.
    have=$(apm GetPackage "$APP_ID" 2>/dev/null | sed -n "s/.*'general.version': '\([^']*\)'.*/\1/p" || true)
    if [ "$have" = "$want" ]; then
        step "пакет $APP_ID $want уже установлен"
    else
        if [ -n "$have" ]; then
            step "удаляю старую версию пакета $have"; apm Remove "$APP_ID" >/dev/null; sleep 3
        fi
        step "ставлю пакет $APP_ID $want (до минуты)"
        apm Install "$f" >/dev/null
        sleep 5
    fi
    # Сторож работает от root: пароль root спрашивается здесь, дальше on и off без него.
    # Если сторож уже работает (замена ссылки), он подхватит новый конфиг при перезапуске.
    on_phone "touch $DIR/on"
    alive watch || { step "запускаю сторожа"; as_root watch; }
    step "включаю туннель"
    on_phone "sh ~/off.sh >/dev/null; sh ~/on.sh"
    step "проверяю, с какого адреса телефон выходит в интернет"
    ip=$(on_phone "curl -4 -s --max-time 10 https://ifconfig.me" || true)
    echo
    echo "Телефон выходит в интернет с адреса ${ip:-(нет ответа)}, сервер из ссылки: $server."
    echo "На телефоне в Терминале: on — включить, off — выключить."
}

# Удаление всего, что поставил install.
remove() {
    # Пароль root нужен, только если работает сторож или туннель.
    step "подключаюсь к телефону $PHONE"
    if alive watch || alive pid; then step "останавливаю сторожа и туннель"; as_root unwatch; fi
    step "удаляю пакет $APP_ID"
    apm Remove "$APP_ID" >/dev/null || echo "пакет не удалился (или его уже нет)"
    on_phone "rm -rf $DIR ~/on.sh ~/off.sh; \
        grep -v -e '^# aurora-xray-tun' -e '^alias on=\"sh ~/on.sh\"' -e '^alias off=\"sh ~/off.sh\"' \
            ~/.bashrc > ~/.bashrc.tmp; cat ~/.bashrc.tmp > ~/.bashrc; rm -f ~/.bashrc.tmp"
    echo "Удалено: пакет, ~/$DIR, ~/on.sh, ~/off.sh и команды on / off из ~/.bashrc."
}

case "${1:-}" in
vless://*) install "$1" ;;
remove) remove ;;
*) echo "запуск: ./setup.sh 'vless://...' [адрес телефона]   или   ./setup.sh remove [адрес телефона]"; exit 2 ;;
esac
