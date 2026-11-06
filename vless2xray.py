#!/usr/bin/env python3
"""Превращает ссылку vless:// в конфиг Xray-core с TUN для всего телефона.

Запуск: python3 vless2xray.py [--ipv6] 'vless://UUID@host:port?...#имя' > xray.json

Поддерживается: security none/tls/reality; type tcp (raw), ws, grpc, httpupgrade, xhttp;
flow (xtls-rprx-vision), шифрование VLESS (encryption). Адрес сервера в dns.hosts
подставляет phone/vless.sh перед каждым запуском, так что DNS телефона не важен.
"""
import ipaddress
import json
import sys
from urllib.parse import parse_qs, unquote, urlsplit

# Локальные сети ходят напрямую, мимо сервера.
PRIVATE = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8",
           "169.254.0.0/16", "fc00::/7", "fe80::/10", "::1/128"]


def fail(msg):
    sys.stderr.write("vless2xray: " + msg + "\n")
    sys.exit(1)


def is_ip(host):
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


def parse(link):
    u = urlsplit(link.strip())
    if u.scheme != "vless":
        fail("это не ссылка vless://")
    try:
        port = u.port
    except ValueError:
        fail("в ссылке неверный порт")
    if not u.username or not u.hostname or not port:
        fail("в ссылке нужны UUID@адрес:порт")
    q = {k: v[0] for k, v in parse_qs(u.query, keep_blank_values=True).items()}
    return u, port, q


def stream_settings(u, q):
    net = q.get("type", "tcp")
    s = {}
    if net in ("tcp", "raw"):
        if q.get("headerType", "none") != "none":
            fail("type=tcp с headerType=%s не поддерживается" % q["headerType"])
        s["network"] = "raw"
    elif net == "ws":
        s["network"] = "ws"
        s["wsSettings"] = {"path": q.get("path", "/")}
        if q.get("host"):
            s["wsSettings"]["host"] = q["host"]
    elif net == "grpc":
        s["network"] = "grpc"
        s["grpcSettings"] = {"serviceName": q.get("serviceName", ""), "multiMode": q.get("mode") == "multi"}
    elif net == "httpupgrade":
        s["network"] = "httpupgrade"
        s["httpupgradeSettings"] = {"path": q.get("path", "/")}
        if q.get("host"):
            s["httpupgradeSettings"]["host"] = q["host"]
    elif net in ("xhttp", "splithttp"):
        s["network"] = "xhttp"
        x = {"path": q.get("path", "/"), "mode": q.get("mode", "auto")}
        if q.get("host"):
            x["host"] = q["host"]
        if q.get("extra"):
            try:
                x["extra"] = json.loads(q["extra"])
            except ValueError:
                fail("extra= не является корректным JSON")
        s["xhttpSettings"] = x
    else:
        fail("type=%s не поддерживается" % net)

    sec = q.get("security", "none")
    if sec == "tls":
        tls = {"serverName": q.get("sni") or q.get("host") or u.hostname, "fingerprint": q.get("fp") or "chrome"}
        if q.get("alpn"):
            tls["alpn"] = q["alpn"].split(",")
        if q.get("pcs"):
            tls["pinnedPeerCertSha256"] = q["pcs"]
        elif q.get("allowInsecure") == "1" or q.get("insecure") == "1":
            fail("Xray больше не принимает allowInsecure; укажите SHA-256 сертификата сервера в pcs=")
        s["security"] = "tls"
        s["tlsSettings"] = tls
    elif sec == "reality":
        if not q.get("pbk"):
            fail("для security=reality нужен pbk (публичный ключ сервера)")
        r = {"serverName": q.get("sni") or u.hostname, "fingerprint": q.get("fp") or "chrome",
             "publicKey": q["pbk"], "shortId": q.get("sid", ""), "spiderX": q.get("spx", "")}
        if q.get("pqv"):
            r["mldsa65Verify"] = q["pqv"]
        s["security"] = "reality"
        s["realitySettings"] = r
    elif sec != "none":
        fail("security=%s не поддерживается" % sec)
    # До самого сервера Xray всегда ходит по IPv4: под этот адрес vless.sh ставит маршрут.
    s["sockopt"] = {"domainStrategy": "UseIPv4"}
    return s


def config(link, ipv6=False):
    u, port, q = parse(link)
    user = {"id": unquote(u.username), "encryption": q.get("encryption") or "none"}
    if q.get("flow"):
        user["flow"] = q["flow"]
    gateway = ["172.19.0.1/30"]
    routes = ["0.0.0.0/1", "128.0.0.0/1"]
    if ipv6:
        gateway.append("fdfe:dcba:9876::1/126")
        routes += ["::/1", "8000::/1"]
    dns = {
        # DNS-запросы приложений телефона Xray отвечает сам, через сервер.
        "tag": "dns-internal",
        "servers": ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"],
        "queryStrategy": "UseIP" if ipv6 else "UseIPv4",
    }
    if not is_ip(u.hostname):
        # Сюда vless.sh перед каждым запуском пишет настоящий адрес сервера.
        dns["hosts"] = {u.hostname: "0.0.0.0"}
    return {
        "log": {"loglevel": "warning"},
        "dns": dns,
        "inbounds": [{
            "tag": "tun", "protocol": "tun",
            "settings": {"name": "xtun0", "mtu": 1400, "gateway": gateway,
                         "autoSystemRoutingTable": routes},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True},
        }],
        "outbounds": [
            {"protocol": "vless", "tag": "proxy",
             "settings": {"vnext": [{"address": u.hostname, "port": port, "users": [user]}]},
             "streamSettings": stream_settings(u, q)},
            {"protocol": "freedom", "tag": "direct"},
            {"protocol": "dns", "tag": "dns-out"},
        ],
        "routing": {
            "domainStrategy": "AsIs",
            "rules": [
                {"type": "field", "inboundTag": ["tun"], "port": "53", "outboundTag": "dns-out"},
                {"type": "field", "inboundTag": ["dns-internal"], "outboundTag": "proxy"},
                {"type": "field", "ip": PRIVATE, "outboundTag": "direct"},
                {"type": "field", "inboundTag": ["tun"], "outboundTag": "proxy"},
            ],
        },
    }


if __name__ == "__main__":
    args = sys.argv[1:]
    ipv6 = "--ipv6" in args
    args = [a for a in args if a != "--ipv6"]
    if len(args) != 1:
        fail("запуск: vless2xray.py [--ipv6] 'vless://...'")
    json.dump(config(args[0], ipv6), sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
