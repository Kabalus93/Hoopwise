#!/usr/bin/env python3
# Hoopwise <-> Claude Desktop bridge (MCP over stdio).
#
# Claude Desktop starts this script and talks MCP to it on stdin/stdout; it
# passes each message to the Hoopwise Mac app, which listens on 127.0.0.1 only
# (Services/ClaudeConnector/ConnectorServer.swift). Claude Desktop's config
# supplies HOOPWISE_URL and HOOPWISE_TOKEN (copy them from the app: Profile ->
# Claude Desktop). Standard library only.
import json, os, sys, urllib.error, urllib.request

URL = os.environ.get("HOOPWISE_URL", "http://127.0.0.1:47720/mcp")
TOKEN = os.environ.get("HOOPWISE_TOKEN", "")

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    request = urllib.request.Request(
        URL, data=line.encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + TOKEN})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        message = json.loads(line) if line.startswith("{") else {}
        body = ""
        if "id" in message:
            text = ("The Hoopwise access key is wrong. Copy the setup again from the app: Profile -> Claude Desktop."
                    if error.code == 401 else "Hoopwise refused the request (HTTP %d)." % error.code)
            body = json.dumps({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32001, "message": text}})
    except Exception as error:
        try:
            message = json.loads(line)
        except ValueError:
            message = {}
        body = ""
        if "id" in message:
            body = json.dumps({"jsonrpc": "2.0", "id": message["id"], "error": {
                "code": -32000,
                "message": "Hoopwise is not reachable on this Mac. Open the Hoopwise app and try again. (%s)" % error}})
    if body.strip():
        sys.stdout.write(body.strip() + "\n")
        sys.stdout.flush()
