#!/usr/bin/env python3
"""Exchange a Steam session ticket for an EOS access token.

Keep this flow aligned with asa_server_list.py, which is the verified auth
reference for Steam session ticket -> EOS user token exchange.
"""

import base64
import json
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

EOS_BASIC_AUTH = "Basic eHl6YTc4OTFxQzVyTXhmMGU3NkI0bEdlNXFlUFFYTnk6MTRCaVpxTFJja1ZKNDlkOWZaWTAvblVveW8rZFEyWjdrOHVySW51Z3ZINA=="
EOS_DEPLOYMENT_ID = "ad9a8feffb3b4b2ca315546f038c3ae2"


def exchange(ticket_hex: str) -> int:
    ticket_hex = ticket_hex.strip().upper()
    if not ticket_hex:
        print("EOS exchange failed: empty Steam session ticket", file=sys.stderr)
        return 1

    nonce = base64.urlsafe_b64encode(secrets.token_bytes(16)).decode("ascii").rstrip("=")
    form = urllib.parse.urlencode(
        {
            "grant_type": "external_auth",
            "external_auth_type": "steam_session_ticket",
            "external_auth_token": ticket_hex,
            "deployment_id": EOS_DEPLOYMENT_ID,
            "nonce": nonce,
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        "https://api.epicgames.dev/auth/v1/oauth/token",
        data=form,
        method="POST",
        headers={
            "Authorization": EOS_BASIC_AUTH,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            result = {
                "token": data["access_token"],
                "expires_in": data.get("expires_in", 3600),
                "expires_at": int(time.time()) + data.get("expires_in", 3600),
                "refreshed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            print(json.dumps(result))
            return 0
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"EOS exchange failed (HTTP {exc.code}): {body}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"EOS exchange failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: eos_token.py <hex_steam_ticket>", file=sys.stderr)
        sys.exit(2)
    sys.exit(exchange(sys.argv[1]))
