#!/bin/bash
# Внутри образа Aurora Platform SDK: package.sh <имя пакета> <версия> <архитектура>
# Берёт /work/src/<имя пакета> (программу) и /work/keys/regular_{key,cert}.pem.
# Собирает RPM, подписывает, проверяет rpm-validator и кладёт RPM в /work/out.
set -euo pipefail
APP=$1 VER=$2 ARCH=$3
TOP=/tmp/rpmbuild
rm -rf $TOP && mkdir -p $TOP/{SOURCES,SPECS}
cp /work/src/$APP $TOP/SOURCES/
cp -r /work/package/icons $TOP/SOURCES/
sed -e "s/@APP@/$APP/g" -e "s/@ORG@/${APP%.*}/g" -e "s/@NAME@/${APP##*.}/g" \
    /work/package/app.desktop.in > $TOP/SOURCES/$APP.desktop
sed -e "s/@APP@/$APP/g" -e "s/@VERSION@/$VER/g" /work/package/app.spec.in > $TOP/SPECS/$APP.spec
rpmbuild -bb --target "$ARCH" --define "_topdir $TOP" $TOP/SPECS/$APP.spec >/tmp/rpmbuild.log 2>&1 \
    || { tail -30 /tmp/rpmbuild.log; exit 1; }
RPM=$(ls $TOP/RPMS/$ARCH/$APP-$VER-*.rpm)
rpmsign-external sign --key /work/keys/regular_key.pem --cert /work/keys/regular_cert.pem "$RPM"
rpmsign-external verify "$RPM"
rpm-validator -p regular "$RPM" >/tmp/validator.log 2>&1 || true
if grep -q ERROR /tmp/validator.log; then grep -E 'ERROR|WARNING' /tmp/validator.log; exit 1; fi
mkdir -p /work/out && cp "$RPM" /work/out/
echo "пакет готов: out/$(basename "$RPM")"
