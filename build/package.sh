#!/bin/bash
# Упаковывает Xray-core в подписанный RPM. Запускается build.sh внутри образа
# Aurora Platform SDK (там есть rpmbuild, rpmsign-external и rpm-validator).
#
# Запуск: package.sh <имя пакета> <версия> <архитектура>
#   имя пакета   например io.github.hunterewok.XrayTun; так же называется программа
#   версия       версия Xray без «v», например 26.10.31
#   архитектура  armv7hl или aarch64
# Берёт:  /work/src/<имя пакета>            программу, собранную build/xray.sh
#         /work/keys/regular_{key,cert}.pem ключ и сертификат подписи
# Кладёт: /work/out/<имя пакета>-<версия>-1.<архитектура>.rpm
set -euo pipefail
APP=$1 VER=$2 ARCH=$3
TOP=/tmp/rpmbuild
rm -rf $TOP && mkdir -p $TOP/{SOURCES,SPECS}
cp /work/src/$APP $TOP/SOURCES/

# Значки. Установщик Авроры не принимает пакет без .desktop-файла и значков четырёх
# размеров (ошибка BadPackage). Значок нигде не показывается (в .desktop стоит
# NoDisplay=true), поэтому вместо картинок здесь рисуются чёрные квадраты нужных
# размеров. Их проще сгенерировать при сборке, чем хранить в репозитории.
python3 - $TOP/SOURCES/icons <<'PY'
import os, struct, sys, zlib
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
def chunk(kind, data):  # блок PNG: длина, тип, данные, CRC
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
for n in (86, 108, 128, 172):
    raw = (b"\0" + b"\0\0\0" * n) * n  # n строк: байт фильтра и n чёрных точек RGB
    with open(os.path.join(out, "%d.png" % n), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
PY

# .desktop и spec из шаблонов: @APP@ — имя пакета, @ORG@ и @NAME@ — его части до и
# после последней точки (их требует раздел [X-Application]).
sed -e "s/@APP@/$APP/g" -e "s/@ORG@/${APP%.*}/g" -e "s/@NAME@/${APP##*.}/g" \
    /work/build/app.desktop.in > $TOP/SOURCES/$APP.desktop
sed -e "s/@APP@/$APP/g" -e "s/@VERSION@/$VER/g" /work/build/app.spec.in > $TOP/SPECS/$APP.spec

# Сборка RPM. Журнал показываем, только если что-то пошло не так.
rpmbuild -bb --target "$ARCH" --define "_topdir $TOP" $TOP/SPECS/$APP.spec >/tmp/rpmbuild.log 2>&1 \
    || { tail -30 /tmp/rpmbuild.log; exit 1; }
RPM=$(ls $TOP/RPMS/$ARCH/$APP-$VER-*.rpm)

# Подпись и проверка подписи.
rpmsign-external sign --key /work/keys/regular_key.pem --cert /work/keys/regular_cert.pem "$RPM"
rpmsign-external verify "$RPM"

# Та же проверка, что делает телефон при установке (профиль Regular). Предупреждения
# (например, про rpath) допустимы, ошибки — нет.
rpm-validator -p regular "$RPM" >/tmp/validator.log 2>&1 || true
if grep -q ERROR /tmp/validator.log; then grep -E 'ERROR|WARNING' /tmp/validator.log; exit 1; fi

mkdir -p /work/out && cp "$RPM" /work/out/
echo "пакет готов: out/$(basename "$RPM")"
