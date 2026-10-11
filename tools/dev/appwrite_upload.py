#!/usr/bin/env python3
"""Chunked upload of a site/function deployment to Appwrite (5 MB parts, the
same protocol the SDKs use). Usage:
  appwrite_upload.py <endpoint> <project> <key> <path e.g. /sites/ID/deployments> <tar.gz> [activate]
Prints the deployment id."""
import json, os, sys, urllib.request, uuid

ep, project, key, path, tar = sys.argv[1:6]
activate = (sys.argv[6] if len(sys.argv) > 6 else 'true')
CHUNK = 5 * 1024 * 1024
size = os.path.getsize(tar)
dep_id = None
with open(tar, 'rb') as f:
    start = 0
    while start < size:
        chunk = f.read(CHUNK)
        end = start + len(chunk) - 1
        boundary = uuid.uuid4().hex
        body = b''
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="activate"\r\n\r\n{activate}\r\n'.encode()
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="code"; filename="code.tar.gz"\r\nContent-Type: application/gzip\r\n\r\n'.encode() + chunk + b'\r\n'
        body += f'--{boundary}--\r\n'.encode()
        headers = {
            'X-Appwrite-Project': project, 'X-Appwrite-Key': key,
            'Content-Type': f'multipart/form-data; boundary={boundary}',
            'Content-Range': f'bytes {start}-{end}/{size}',
        }
        if dep_id:
            headers['x-appwrite-id'] = dep_id
        req = urllib.request.Request(ep + path, data=body, headers=headers, method='POST')
        try:
            resp = json.loads(urllib.request.urlopen(req, timeout=300).read())
        except urllib.error.HTTPError as e:
            sys.exit(f'upload failed at {start}: {e.code} {e.read()[:300].decode()}')
        dep_id = resp.get('$id') or dep_id
        print(f'  {min(end + 1, size) * 100 // size}%', file=sys.stderr, flush=True)
        start = end + 1
print(dep_id)
