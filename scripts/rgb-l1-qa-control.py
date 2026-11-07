#!/usr/bin/env python3.13
"""Public-only manual QA journal. This program never operates a wallet or stack."""
import argparse
import hashlib
import http.server
import json
import math
import os
from pathlib import Path
import re
import threading
import uuid

MAX_BYTES = 64 * 1024
TOKEN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,179}$')
PRIVATE = re.compile(r'password|mnemonic|seed|secret|private.?key|token|cookie', re.I)
FINANCIAL_REQUESTS = {'fund_requested', 'rgb_witness_funding_requested', 'rgb_setup_confirm_requested', 'btc_confirm_requested'}


def decode_public(raw):
    if len(raw) > MAX_BYTES:
        raise ValueError('oversized')
    def pairs(entries):
        result = {}
        for key, value in entries:
            if key in result:
                raise ValueError('duplicate-key')
            result[key] = value
        return result
    def invalid_constant(_):
        raise ValueError('nonfinite')
    result = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_constant)
    def check(value, depth=0):
        if depth > 12:
            raise ValueError('too-deep')
        if isinstance(value, dict):
            for key, item in value.items():
                if PRIVATE.search(key):
                    raise ValueError('private-field')
                check(item, depth + 1)
        elif isinstance(value, list):
            for item in value:
                check(item, depth + 1)
        elif isinstance(value, str):
            if len(value) > 8192:
                raise ValueError('oversized-field')
        elif isinstance(value, float) and not math.isfinite(value):
            raise ValueError('nonfinite')
    check(result)
    if not isinstance(result, dict):
        raise ValueError('object-required')
    return result


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()


def read_bounded(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('oversized')
    return raw


def exclusive(path, value):
    raw = canonical(value)
    if len(raw) > MAX_BYTES:
        raise ValueError('oversized')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


class Journal:
    def __init__(self, root, run_id):
        if not TOKEN.fullmatch(run_id) or len(run_id) > 64:
            raise ValueError('invalid-run')
        self.root, self.run_id = Path(root), run_id
        self.lock = threading.Lock()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in ['events', 'commands']:
            directory = self.root / name
            if directory.is_symlink():
                raise ValueError('unsafe-directory')
            directory.mkdir(mode=0o700, exist_ok=True)
        scope = self.root / 'scope.json'
        expected = {'version': 1, 'runId': run_id, 'financialExecution': 'manual-only', 'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        if scope.exists():
            if decode_public(read_bounded(scope)) != expected:
                raise ValueError('different-scope')
        else:
            exclusive(scope, expected)

    def event(self, value):
        value = decode_public(canonical(value))
        role, event = value.get('role'), value.get('event')
        if value.get('run_id') != self.run_id or not isinstance(role, str) or not isinstance(event, str) or not TOKEN.fullmatch(role) or not TOKEN.fullmatch(event):
            raise ValueError('wrong-context')
        identity = value.get('id')
        if identity is None:
            if value['event'] in FINANCIAL_REQUESTS:
                raise ValueError('financial-id-required')
            identity = uuid.uuid4().hex
        elif not isinstance(identity, str) or not TOKEN.fullmatch(identity) or not identity.startswith(self.run_id + '-' + value['role'] + '-'):
            raise ValueError('wrong-request-id')
        path = self.root / 'events' / (identity + '.json')
        with self.lock:
            if path.exists():
                if path.is_symlink() or read_bounded(path) != canonical(value):
                    raise ValueError('conflicting-request')
                return identity, True
            exclusive(path, value)
        return identity, False

    def reply(self, identity, value):
        value = decode_public(canonical(value))
        if not TOKEN.fullmatch(identity) or value.get('ok') is not True:
            raise ValueError('invalid-reply')
        event = self.root / 'events' / (identity + '.json')
        if not event.is_file() or event.is_symlink() or decode_public(read_bounded(event)).get('id') != identity:
            raise ValueError('missing-request')
        with self.lock:
            exclusive(self.root / 'commands' / (identity + '.json'), value)

    def command(self, identity):
        if not TOKEN.fullmatch(identity):
            raise ValueError('invalid-command')
        path = self.root / 'commands' / (identity + '.json')
        if path.is_symlink():
            raise ValueError('unsafe-command')
        return read_bounded(path) if path.is_file() else None


def serve(journal, port):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def respond(self, code, value):
            body = canonical(value)
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_POST(self):
            try:
                length = int(self.headers.get('Content-Length', '-1'))
                if self.path != '/event' or length < 0 or length > MAX_BYTES:
                    raise ValueError('invalid-request')
                identity, duplicate = journal.event(decode_public(self.rfile.read(length)))
                self.respond(200, {'ok': True, 'id': identity, 'duplicate': duplicate})
            except (ValueError, OSError):
                self.respond(409, {'ok': False, 'reason': 'journal-rejected'})
        def do_GET(self):
            try:
                if not self.path.startswith('/commands/'):
                    raise ValueError('invalid-path')
                raw = journal.command(self.path[len('/commands/'):])
                self.respond(404, {'ok': False}) if raw is None else self.respond(200, decode_public(raw))
            except (ValueError, OSError):
                self.respond(400, {'ok': False})
    http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['serve', 'reply'])
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--port', type=int, default=29671)
    parser.add_argument('--id')
    parser.add_argument('--payload-file', type=Path)
    args = parser.parse_args()
    allowed = Path(__file__).resolve().parents[1] / '.buildlog' / 'rgb-l1-full-flow'
    if args.root.resolve().parent != allowed.resolve() or args.root.name != args.run_id or args.root.is_symlink():
        parser.error('Use one owned .buildlog/rgb-l1-full-flow/<run-id> directory.')
    journal = Journal(args.root, args.run_id)
    if args.action == 'serve':
        if not 1024 <= args.port <= 65535:
            parser.error('An unprivileged loopback port is required.')
        serve(journal, args.port)
    else:
        if args.id is None or args.payload_file is None:
            parser.error('Reply requires --id and --payload-file.')
        journal.reply(args.id, decode_public(read_bounded(args.payload_file)))


if __name__ == '__main__':
    main()
