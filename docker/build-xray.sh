#!/bin/sh
# Внутри образа xray: build-xray.sh <тег Xray> <armv7hl|aarch64> <файл результата>
# Проверка пакетов Авроры требует динамическую программу, которая связана с glibc и
# экспортирует main(). Поэтому Xray собирается с cgo, как PIE, с --export-dynamic.
set -eu
TAG=$1 ARCH=$2 OUT=$3
case $ARCH in
armv7hl) export GOARCH=arm GOARM=7 CC=arm-linux-gnueabihf-gcc LD=/lib/ld-linux-armhf.so.3 ;;
aarch64) export GOARCH=arm64 CC=aarch64-linux-gnu-gcc LD=/lib/ld-linux-aarch64.so.1 ;;
*) echo "неизвестная архитектура $ARCH"; exit 2 ;;
esac
SRC=/cache/Xray-core-$TAG
[ -d "$SRC" ] || git clone -q --depth 1 -b "$TAG" https://github.com/XTLS/Xray-core "$SRC"
cd "$SRC"
export CGO_ENABLED=1 GOOS=linux GOCACHE=/cache/go-build GOMODCACHE=/cache/go-mod
go build -trimpath -buildmode=pie -o "$OUT" \
    -ldflags "-s -w -buildid= -linkmode external -extldflags '-Wl,--export-dynamic -Wl,--dynamic-linker=$LD'" \
    ./main
echo "собран $OUT"
