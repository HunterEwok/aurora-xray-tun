#!/bin/sh
# Собирает Xray-core для телефона. Запускается build.sh внутри образа build/Dockerfile.
#
# Запуск: xray.sh <тег Xray> <архитектура> <файл результата>
#   тег Xray     тег из github.com/XTLS/Xray-core, например v26.10.31
#   архитектура  armv7hl (32-битная система) или aarch64 (64-битная)
#   файл         куда положить программу, например /src/io.github.hunterewok.XrayTun
# Исходники и кэш Go лежат в /cache (папка cache/ рядом с build.sh), поэтому повторная
# сборка идёт быстро.
#
# Проверка пакетов Авроры требует динамическую программу, которая связана с glibc и
# экспортирует main(). Поэтому Xray собирается с cgo, как PIE, с --export-dynamic.
set -eu
TAG=$1 ARCH=$2 OUT=$3
# Кросс-компилятор и путь к загрузчику glibc на телефоне для каждой архитектуры.
case $ARCH in
armv7hl) export GOARCH=arm GOARM=7 CC=arm-linux-gnueabihf-gcc LD=/lib/ld-linux-armhf.so.3 ;;
aarch64) export GOARCH=arm64 CC=aarch64-linux-gnu-gcc LD=/lib/ld-linux-aarch64.so.1 ;;
*) echo "неизвестная архитектура $ARCH"; exit 2 ;;
esac
# Исходники нужного тега скачиваются один раз.
SRC=/cache/Xray-core-$TAG
[ -d "$SRC" ] || git clone -q --depth 1 -b "$TAG" https://github.com/XTLS/Xray-core "$SRC"
cd "$SRC"
export CGO_ENABLED=1 GOOS=linux GOCACHE=/cache/go-build GOMODCACHE=/cache/go-mod
# -trimpath, -s -w и пустой buildid убирают из программы пути и отладочные данные.
go build -trimpath -buildmode=pie -o "$OUT" \
    -ldflags "-s -w -buildid= -linkmode external -extldflags '-Wl,--export-dynamic -Wl,--dynamic-linker=$LD'" \
    ./main
echo "собран $OUT"
