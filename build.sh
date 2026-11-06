#!/bin/sh
# Собирает Xray-core подписанным пакетом Авроры в папку out/:
#   out/<имя пакета>-<версия>-1.<арх>.rpm
# Собирать самому не обязательно: готовые пакеты лежат в релизах на GitHub, и
# setup.sh скачивает их сам. Сборка нужна для своей версии Xray, своего имени
# пакета или своего ключа подписи.
#
# Запуск: ./build.sh
# Настройки (переменные окружения):
#   ARCH=armv7hl|aarch64|all   архитектура телефона (по умолчанию armv7hl)
#   APP_ID=...                 имя пакета (по умолчанию io.github.hunterewok.XrayTun)
#   XRAY_VERSION=v...          тег Xray-core
# Нужен Docker. Тестовые ключи подписи скачиваются сами (см. keys/README.md).
set -eu
cd "$(dirname "$0")"

ARCH=${ARCH:-armv7hl}
APP_ID=${APP_ID:-io.github.hunterewok.XrayTun}
XRAY_VERSION=${XRAY_VERSION:-v26.10.31}
PSDK_VERSION=5.1.5.105
PSDK_IMAGE=aurora-psdk:$PSDK_VERSION
PSDK_URL=https://sdk-repo.omprussia.ru/sdk/installers/5.1.5/$PSDK_VERSION-release/AuroraPSDK/Aurora_OS-$PSDK_VERSION-MB2-Aurora_Platform_SDK_Chroot-x86_64.tar.bz2
XRAY_IMAGE=aurora-xray-tun-build:1

# Публичная тестовая пара ОМП для профиля Regular («Noname developer, for testing only»).
KEYS_BASE=${KEYS_BASE:-https://developer.auroraos.ru/content-images/dev-documentation}
KEY_SHA256=5d0d87728ddb719dcd506635b093efd2da303a990e0085c885d53aeb5282d6c5
CERT_SHA256=2ad68fead24760f9dc2a56274c2fd77ee3426ecdc7360890af459d81b8e2af86

die() { echo "build.sh: $*" >&2; exit 1; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

case $ARCH in
armv7hl|aarch64) ARCHS=$ARCH ;;
all) ARCHS="armv7hl aarch64" ;;
*) die "ARCH должен быть armv7hl, aarch64 или all" ;;
esac
command -v docker >/dev/null || die "не установлен Docker"
mkdir -p out src cache keys

# 1. Ключи подписи: скачиваем и сверяем контрольные суммы. Свои ключи (например,
# выданные ОМП) можно положить в keys/ заранее: тогда они не скачиваются.
for f in regular_key.pem:$KEY_SHA256 regular_cert.pem:$CERT_SHA256; do
    name=${f%%:*} sum=${f#*:}
    [ -f keys/$name ] && continue
    echo "скачиваю keys/$name"
    curl -fsSL "$KEYS_BASE/$name" -o keys/$name.tmp || die "не удалось скачать $KEYS_BASE/$name (см. keys/README.md)"
    [ "$(sha256 keys/$name.tmp)" = "$sum" ] || { rm -f keys/$name.tmp; die "у скачанного $name другая контрольная сумма"; }
    mv keys/$name.tmp keys/$name
done

# 2. Образы: сборка Xray и Aurora Platform SDK. SDK — образ x86_64: на Маке с
# Apple Silicon Docker запускает его через эмуляцию.
docker build -q -t $XRAY_IMAGE -f docker/xray.Dockerfile docker >/dev/null
if ! docker image inspect $PSDK_IMAGE >/dev/null 2>&1; then
    echo "загружаю Aurora Platform SDK $PSDK_VERSION (один раз, около 600 МБ)"
    docker import --platform linux/amd64 "$PSDK_URL" $PSDK_IMAGE >/dev/null
fi

# 3. Для каждой архитектуры: Xray-core, потом пакет с подписью.
# -it: свой ключ с паролем подпись спросит в терминале.
TTY=; [ -t 0 ] && TTY=-it
for A in $ARCHS; do
    docker run --rm -v "$PWD/cache:/cache" -v "$PWD/src:/src" $XRAY_IMAGE \
        "$XRAY_VERSION" "$A" "/src/$APP_ID"
    docker run --rm $TTY --platform linux/amd64 -v "$PWD:/work" $PSDK_IMAGE /bin/bash -c \
        "/bin/bash /work/docker/package.sh '$APP_ID' '${XRAY_VERSION#v}' '$A' && chown -R $(id -u):$(id -g) /work/out /work/src"
done

echo
echo "Готово. Дальше: ./setup.sh 'vless://...'   (см. README.md)"
