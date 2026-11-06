#!/bin/sh
# Выключить VLESS: sh off.sh (спросит пароль root)
devel-su sh "$HOME/xray-tun/vless.sh" stop
