#!/usr/bin/env python3
"""Send files with localsend-cli, presenting the TLS client certificate LocalSend expects.

`localsend-cli send` (0.1.1) builds its requests session with verify=False but never
loads its own certificate. LocalSend 2.x receivers require mutual TLS, so they abort
the handshake and the send dies with:

    SSLError(SSL: TLSV13_ALERT_CERTIFICATE_REQUIRED) tlsv13 alert certificate required

The CLI also allows only 10 seconds for the receiver to approve a transfer, which is
shorter than a person usually needs to look at the other device. This wrapper reuses
the CLI's protocol code and fixes both, so qs.services.LocalSend keeps one send path.

Usage:
    <localsend-cli interpreter> localsend-send.py send <ip> <file>... [--json]
"""

import json
import sys

import requests
from localsend_cli.commands import send as send_command
from localsend_cli.constants import CERT_FILE, KEY_FILE
from localsend_cli.crypto import ensure_cert

# The receiving device has to be approved by a human before prepare-upload returns.
APPROVAL_TIMEOUT = 180


class CertSession(requests.Session):
    """requests session that authenticates with this machine's LocalSend certificate."""

    def __init__(self):
        super().__init__()
        self.verify = False
        self.cert = (str(CERT_FILE), str(KEY_FILE))

    def post(self, url, **kwargs):
        if "prepare-upload" in url:
            kwargs["timeout"] = APPROVAL_TIMEOUT
        return super().post(url, **kwargs)


def main():
    ensure_cert()
    send_command.requests.Session = CertSession
    # Imported here so the session patch is in place before the CLI module loads.
    from localsend_cli.main import main as cli_main

    return cli_main() or 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # keep failures machine readable for the shell
        print(json.dumps({"event": "error", "message": f"{type(exc).__name__}: {exc}"}), flush=True)
        sys.exit(1)
