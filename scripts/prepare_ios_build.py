"""Prepare only a disposable CI checkout; never embeds provider keys."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import plistlib
from urllib.parse import urlsplit


def validate_backend(url, allow_local_http=False, signed=False):
    parsed = urlsplit(url.strip())
    host = (parsed.hostname or '').lower()
    if (not host or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ('', '/') or host in ('localhost', '0.0.0.0')
            or host.endswith('.invalid')):
        raise ValueError('Set API_BASE_URL to a reachable backend origin, without credentials or paths.')
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address and (address.is_loopback or address.is_unspecified or address.is_link_local):
        raise ValueError('iPhone cannot use this local/loopback address. Use the Windows LAN IPv4 address.')
    if parsed.scheme == 'https':
        return url.rstrip('/'), False
    private_ipv4 = address is not None and address.version == 4 and any(address in block for block in (
        ipaddress.ip_network('10.0.0.0/8'), ipaddress.ip_network('172.16.0.0/12'), ipaddress.ip_network('192.168.0.0/16')))
    if parsed.scheme == 'http' and private_ipv4 and allow_local_http and not signed:
        return url.rstrip('/'), True
    raise ValueError('Use HTTPS. LAN HTTP is allowed only for unsigned testing with IOS_ALLOW_LOCAL_HTTP=1.')


def prepare(root, env, signed=False):
    url, local_http = validate_backend(env.get('API_BASE_URL', ''), env.get('IOS_ALLOW_LOCAL_HTTP') == '1', signed)
    info_path = root / 'mobile/ios/Runner/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if local_http:
        # Build-only test setting. Never written to the committed production plist.
        info['NSLocalNetworkUsageDescription'] = 'TrafficGo kết nối backend trên máy tính trong cùng mạng Wi-Fi để thử nghiệm bản đồ và hành trình.'
        info['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True}
    elif info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads'):
        raise ValueError('Refusing an unrestricted transport exception in a HTTPS/signed build.')
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    target = root / 'build/ci'
    target.mkdir(parents=True, exist_ok=True)
    (target / 'defines.json').write_text(json.dumps({'API_BASE_URL': url}), encoding='utf-8')
    (target / 'build-config.json').write_text(json.dumps({'mode': 'signed' if signed else 'unsigned', 'local_http_test_only': local_http}), encoding='utf-8')
    print('iOS backend configuration validated; provider keys stay on the backend.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--signed', action='store_true')
    args = parser.parse_args()
    try:
        prepare(Path(__file__).resolve().parents[1], os.environ, args.signed)
    except ValueError as error:
        parser.exit(2, str(error) + '\n')
