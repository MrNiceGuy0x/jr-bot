"""One privileged Guild Overview template; no job-supplied URL or retries."""
from __future__ import annotations
import hashlib
import http.client
import json
import multiprocessing
import os
import re
import ssl
import stat
from html.parser import HTMLParser
from pathlib import Path

class HttpCapabilityError(ValueError):
    pass

POLICY = {
    'capability_id': 'guild_overview_refresh', 'capability_revision': 1,
    'enabled': True, 'network_scope': 'external_https', 'scheme': 'https',
    'host': 'www.blenk.co.at', 'port': 443, 'method': 'GET',
    'path': '/splinterlands/API/guild_overview.php', 'query': {}, 'body': None,
    'headers': {'Accept': 'text/html', 'Accept-Encoding': 'identity'},
    'secret_bindings': {}, 'redirects': False, 'tls_verify': True,
    'connect_timeout_seconds': 10, 'total_timeout_seconds': 60,
    'max_response_bytes': 1048576, 'success_status': [200],
    'response_projection': 'guild_overview_html_v1', 'retry_safety': 'never_auto_retry',
}


def load_policy(base: Path):
    path = base / 'config/capabilities.d/guild_overview.http.json'
    for parent in [path] + list(path.parents):
        if parent.is_symlink():
            raise HttpCapabilityError('HTTP_POLICY_UNSAFE')
    try:
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_size > 8192 or info.st_uid not in {0, os.geteuid()} or info.st_mode & 0o022:
            raise HttpCapabilityError('HTTP_POLICY_UNSAFE')
        def pairs(items):
            value = {}
            for key, item in items:
                if key in value:
                    raise HttpCapabilityError('HTTP_POLICY_INVALID')
                value[key] = item
            return value
        value = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs)
    except (OSError, ValueError) as exc:
        raise HttpCapabilityError('HTTP_POLICY_UNAVAILABLE') from exc
    if json.dumps(value, sort_keys=True) != json.dumps(POLICY, sort_keys=True):
        raise HttpCapabilityError('HTTP_POLICY_INVALID')
    return value


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag not in {'p', 'br'} or attrs:
            raise ValueError('unexpected markup')
        self.parts.append('\n')
    def handle_endtag(self, tag):
        if tag != 'p':
            raise ValueError('unexpected markup')
        self.parts.append('\n')
    def handle_data(self, value): self.parts.append(value)
    def handle_comment(self, value): raise ValueError('unexpected comment')
    def handle_decl(self, value): raise ValueError('unexpected declaration')


def project_response(status, headers, body):
    unknown = {'outcome': 'failed', 'message': 'Guild Overview result unconfirmed; no automatic retry',
               'result': {'confirmation': 'unconfirmed'}}
    if status != 200 or len(body) > POLICY['max_response_bytes'] or headers.get('content-encoding', 'identity').lower() != 'identity':
        return unknown
    try:
        text = _Text(); text.feed(body.decode('utf-8', errors='strict')); text.close()
        lines = [p.strip() for p in ''.join(text.parts).splitlines() if p.strip()]
        if len(lines) < 3:
            return unknown
        count = re.fullmatch(r'Anzahl der abgerufenen Gildenmitglieder: ([1-9][0-9]{0,4})', lines[0])
        if not count or lines[-1] != 'Verarbeitung abgeschlossen. Alle Mitglieder wurden aktualisiert.':
            return unknown
        players = []
        for line in lines[1:-1]:
            player = re.fullmatch(r'([A-Za-z0-9_.-]{1,64}) erfolgreich gespeichert\.', line)
            if player is None:
                return unknown
            players.append(player[1])
        if len(players) != int(count[1]) or len(set(players)) != len(players):
            return unknown
    except (UnicodeError, ValueError):
        return unknown
    return {'outcome': 'succeeded', 'message': 'Guild Overview complete response confirmed',
            'result': {'confirmation': 'complete_response', 'member_count': len(players),
                       'response_sha256': hashlib.sha256(body).hexdigest()}}


def _request(policy):
    connection = http.client.HTTPSConnection(policy['host'], policy['port'],
        timeout=policy['connect_timeout_seconds'], context=ssl.create_default_context())
    try:
        connection.connect()
        connection.sock.settimeout(policy['total_timeout_seconds'])
        connection.request(policy['method'], policy['path'], headers=policy['headers'])
        response = connection.getresponse()
        headers = {k.lower(): v for k, v in response.getheaders()}
        if response.status != 200:
            return project_response(response.status, headers, b'')
        body = response.read(policy['max_response_bytes'] + 1)
        return project_response(response.status, headers, body)
    finally:
        connection.close()


def _worker(pipe, policy):
    try:
        pipe.send(_request(policy))
    except Exception:
        pipe.send({'outcome': 'failed', 'message': 'Guild Overview result unconfirmed; no automatic retry',
                   'result': {'confirmation': 'unconfirmed'}})
    finally:
        pipe.close()


def execute_guild_overview(base, payload):
    if payload != {'action': 'guild_overview_refresh'}:
        raise HttpCapabilityError('HTTP_PAYLOAD_REJECTED')
    policy = load_policy(Path(base))
    # Parent enforces total elapsed budget including DNS/TLS/body trickle.
    context = multiprocessing.get_context('spawn')
    reader, writer = context.Pipe(duplex=False)
    process = context.Process(target=_worker, args=(writer, policy))
    process.start(); writer.close()
    try:
        if reader.poll(policy['total_timeout_seconds']):
            try:
                return reader.recv()
            except EOFError:
                pass
        return {'outcome': 'failed', 'message': 'Guild Overview result unconfirmed; no automatic retry',
                'result': {'confirmation': 'unconfirmed'}}
    finally:
        reader.close()
        if process.is_alive():
            process.terminate()
        process.join(timeout=2)
        if process.is_alive():
            process.kill(); process.join(timeout=2)
