#!/usr/bin/env python3
"""TOTP authenticator backend for the ii Quickshell shell.

QML has no crypto primitives, so codes are generated here. The store is a
plain JSON file so services can also be edited by hand (config editing):

  ~/.config/illogical-impulse/authenticators.json
  {
    "version": 1,
    "services": [
      {
        "id": "3f9c1a...",        // generated, do not need to set by hand
        "issuer": "GitHub",
        "name": "user@example.com",
        "secret": "JBSWY3DPEHPK3PXP",   // base32, spaces/case tolerated
        "digits": 6,
        "period": 30,
        "algorithm": "SHA1"       // SHA1 | SHA256 | SHA512
      }
    ]
  }

A bare JSON array of services is also accepted, and "id" is optional: it is
derived from the entry when missing.

Subcommands (all print JSON on stdout, {"error": ...} + exit 1 on failure):
  stream   Long-running; prints one JSON line per second with every code.
  code     Print the current code of one service (plain text).
  list     Print the stored services.
  add      Add a service.
  update   Change a service (issuer/name/secret/digits/period/algorithm).
  remove   Delete a service.
  import   Import from a JSON export or otpauth:// URI file (or stdin).
  export   Write a JSON or otpauth:// URI export.
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import struct
import sys
import tempfile
import time
import urllib.parse

DEFAULT_STORE = os.path.expanduser("~/.config/illogical-impulse/authenticators.json")
ALGORITHMS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}
DEFAULT_DIGITS = 6
DEFAULT_PERIOD = 30
DEFAULT_ALGORITHM = "SHA1"


# --------------------------------------------------------------------------
# Secrets / codes
# --------------------------------------------------------------------------

class OtpError(Exception):
    pass


def clean_secret(value):
    """Return an unpadded uppercase base32 secret, or raise."""
    secret = re.sub(r"[\s\-]", "", str(value or "")).upper().rstrip("=")
    if not secret:
        raise OtpError("empty secret")
    if not re.fullmatch(r"[A-Z2-7]+", secret):
        raise OtpError("secret is not valid base32")
    return secret


def _b32_decode(secret):
    return base64.b32decode(secret + "=" * ((-len(secret)) % 8))


def totp_code(secret, digits=DEFAULT_DIGITS, period=DEFAULT_PERIOD,
              algorithm=DEFAULT_ALGORITHM, at=None):
    """RFC 6238 TOTP code for the given time (defaults to now)."""
    algo = ALGORITHMS.get(str(algorithm or DEFAULT_ALGORITHM).upper())
    if algo is None:
        raise OtpError(f"unsupported algorithm: {algorithm}")
    counter = int((time.time() if at is None else at) // max(1, int(period)))
    digest = hmac.new(_b32_decode(secret), struct.pack(">Q", counter), algo).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10 ** int(digits))).zfill(int(digits))


def _seconds_left(period, at=None):
    period = max(1, int(period))
    return period - int(time.time() if at is None else at) % period


# --------------------------------------------------------------------------
# Service records
# --------------------------------------------------------------------------

def _first(*values):
    for value in values:
        if isinstance(value, (int, float)):
            return str(value)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _int_or(value, fallback):
    try:
        number = int(str(value).strip())
    except (TypeError, ValueError):
        return fallback
    return number if number > 0 else fallback


def service_id(issuer, name, secret):
    digest = hashlib.sha1(f"{issuer}\0{name}\0{secret}".encode("utf-8")).hexdigest()
    return digest[:12]


def normalise_entry(raw):
    """Turn an entry from any supported export format into a service row.

    Returns None when the entry is not a usable TOTP secret.
    """
    if not isinstance(raw, dict):
        return None
    info = raw.get("info") if isinstance(raw.get("info"), dict) else {}
    otp = raw.get("otp") if isinstance(raw.get("otp"), dict) else {}

    kind = _first(raw.get("type"), raw.get("tokenType"), otp.get("tokenType"),
                  otp.get("type"), info.get("type"), "totp").lower()
    if "hotp" in kind or "counter" in kind:
        return None  # counter-based OTP is not supported

    secret = _first(raw.get("secret"), raw.get("key"), info.get("secret"),
                    otp.get("secret"), raw.get("otp"))
    if not secret:
        return None
    try:
        secret = clean_secret(secret)
    except OtpError:
        return None

    issuer = _first(otp.get("issuer"), info.get("issuer"), raw.get("issuer"),
                    raw.get("service"))
    # Nested account fields are the most specific ones (2FAS keeps the service
    # title at the top level and the account inside "otp").
    name = _first(info.get("name"), info.get("account"), otp.get("name"),
                  otp.get("account"), raw.get("name"), raw.get("label"),
                  raw.get("account"), raw.get("email"), raw.get("note"))
    if ":" in name and not issuer:
        issuer, name = (part.strip() for part in name.split(":", 1))
    if not name and not issuer:
        name = "Unnamed"

    algorithm = _first(raw.get("algorithm"), raw.get("algo"), info.get("algo"),
                       otp.get("algorithm"), DEFAULT_ALGORITHM).upper()
    if algorithm not in ALGORITHMS:
        algorithm = DEFAULT_ALGORITHM
    digits = _int_or(_first(raw.get("digits"), info.get("digits"), otp.get("digits")),
                     DEFAULT_DIGITS)
    period = _int_or(_first(raw.get("period"), info.get("period"), otp.get("period")),
                     DEFAULT_PERIOD)

    return {
        "id": _first(raw.get("id")) or service_id(issuer, name, secret),
        "issuer": issuer,
        "name": name,
        "secret": secret,
        "digits": digits,
        "period": period,
        "algorithm": algorithm,
    }


def entry_from_uri(uri):
    parts = urllib.parse.urlsplit(uri.strip())
    if parts.scheme != "otpauth":
        raise OtpError("not an otpauth:// URI")
    if parts.netloc.lower() != "totp":
        raise OtpError(f"unsupported otpauth type: {parts.netloc}")
    label = urllib.parse.unquote(parts.path.lstrip("/"))
    query = urllib.parse.parse_qs(parts.query)
    issuer = (query.get("issuer") or [""])[0]
    if ":" in label and not issuer:
        issuer, label = (part.strip() for part in label.split(":", 1))
    elif ":" in label:
        label = label.split(":", 1)[1].strip()
    return normalise_entry({
        "issuer": issuer,
        "name": label,
        "secret": (query.get("secret") or [""])[0],
        "digits": (query.get("digits") or [""])[0],
        "period": (query.get("period") or [""])[0],
        "algorithm": (query.get("algorithm") or [""])[0],
        "type": "totp",
    })


def otpauth_uri(service):
    label = f"{service['issuer']}:{service['name']}" if service["issuer"] else service["name"]
    params = {"secret": service["secret"]}
    if service.get("issuer"):
        params["issuer"] = service["issuer"]
    if service.get("algorithm", DEFAULT_ALGORITHM) != DEFAULT_ALGORITHM:
        params["algorithm"] = service["algorithm"]
    if service.get("digits", DEFAULT_DIGITS) != DEFAULT_DIGITS:
        params["digits"] = service["digits"]
    if service.get("period", DEFAULT_PERIOD) != DEFAULT_PERIOD:
        params["period"] = service["period"]
    return f"otpauth://totp/{urllib.parse.quote(label)}?{urllib.parse.urlencode(params)}"


def same_service(left, right):
    return (left["issuer"].lower() == right["issuer"].lower()
            and left["name"].lower() == right["name"].lower()
            and left["secret"] == right["secret"])


# --------------------------------------------------------------------------
# Store I/O
# --------------------------------------------------------------------------

def empty_store():
    return {"version": 1, "services": []}


def load_store(path):
    """Load and normalise the store. Missing/empty/corrupt files load as empty."""
    if not os.path.exists(path):
        return empty_store()
    try:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        raise OtpError(f"cannot read store: {error}")
    if not text.strip():
        return empty_store()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        raise OtpError(f"store is not valid JSON: {error}")

    if isinstance(data, list):
        rows = data
    elif isinstance(data, dict):
        rows = data.get("services")
        if not isinstance(rows, list):
            rows = data.get("entries") if isinstance(data.get("entries"), list) else []
    else:
        rows = []

    services = []
    seen_ids = set()
    for row in rows:
        service = normalise_entry(row)
        if service is None:
            continue
        while service["id"] in seen_ids:
            service["id"] = service["id"] + "x"
        seen_ids.add(service["id"])
        services.append(service)
    return {"version": 1, "services": services}


def save_store(path, store):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    payload = json.dumps(store, indent=2, ensure_ascii=False) + "\n"
    descriptor, temp_path = tempfile.mkstemp(dir=directory, prefix=".authenticators-",
                                             suffix=".json")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.chmod(temp_path, 0o600)
        os.replace(temp_path, path)
    except BaseException:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def emit(payload):
    try:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        # The shell went away (process killed / reloaded); exit quietly.
        raise SystemExit(0)


def fail(message):
    emit({"error": message})
    return 1


def resolve(store, selector):
    """Find a service by id, then by 'issuer:name', then by name/issuer substring."""
    needle = (selector or "").strip().lower()
    if not needle:
        raise OtpError("no service given")
    for service in store["services"]:
        if service["id"].lower() == needle:
            return service
    for service in store["services"]:
        if f"{service['issuer']}:{service['name']}".lower() == needle:
            return service
    matches = [service for service in store["services"]
               if needle in service["name"].lower() or needle in service["issuer"].lower()]
    if not matches:
        raise OtpError(f"no service matches '{selector}'")
    if len(matches) > 1:
        names = ", ".join(f"{s['issuer']}:{s['name']}" for s in matches[:5])
        raise OtpError(f"'{selector}' is ambiguous: {names}")
    return matches[0]


def cmd_stream(args):
    last_signature = None
    store = empty_store()
    while True:
        try:
            stat = os.stat(args.store)
            signature = (stat.st_mtime_ns, stat.st_size)
        except OSError:
            signature = None
        if signature != last_signature:
            last_signature = signature
            try:
                store = load_store(args.store)
            except OtpError as error:
                print(f"[authenticator] {error}", file=sys.stderr, flush=True)
                store = empty_store()

        now = time.time()
        codes = []
        for service in store["services"]:
            try:
                code = totp_code(service["secret"], service["digits"],
                                 service["period"], service["algorithm"], now)
            except (OtpError, ValueError, base64.binascii.Error):
                continue
            codes.append({
                "id": service["id"],
                "code": code,
                "period": service["period"],
                "remaining": _seconds_left(service["period"], now),
            })
        emit({"type": "codes", "services": codes})
        # Wake on the next second boundary so the countdown stays accurate.
        time.sleep(max(0.02, 1.0 - (time.time() % 1.0)))


def cmd_code(args):
    store = load_store(args.store)
    service = resolve(store, args.selector)
    sys.stdout.write(totp_code(service["secret"], service["digits"],
                               service["period"], service["algorithm"]) + "\n")
    sys.stdout.flush()
    return 0


def cmd_list(args):
    store = load_store(args.store)
    emit({"services": store["services"], "count": len(store["services"])})
    return 0


def _labelled(issuer, name):
    if issuer and name:
        return f"{issuer}:{name}"
    return issuer or name


def cmd_add(args):
    store = load_store(args.store)
    issuer = (args.issuer or "").strip()
    name = (args.name or "").strip()
    if args.label:
        label = args.label.strip()
        if ":" in label:
            label_issuer, label_name = (part.strip() for part in label.split(":", 1))
            issuer = issuer or label_issuer
            name = name or label_name
        else:
            name = name or label
    if not name and not issuer:
        raise OtpError("give the service a name, e.g. add GitHub:me@example.com SECRET")

    service = normalise_entry({
        "issuer": issuer,
        "name": name,
        "secret": args.secret,
        "digits": args.digits,
        "period": args.period,
        "algorithm": args.algorithm,
        "type": "totp",
    })
    if service is None:
        raise OtpError("that secret is not valid base32")
    for existing in store["services"]:
        if same_service(existing, service):
            raise OtpError(f"{_labelled(service['issuer'], service['name'])} already exists")
        if existing["id"] == service["id"]:
            service["id"] = service_id(service["issuer"], service["name"],
                                       service["secret"] + "!")
    store["services"].append(service)
    save_store(args.store, store)
    emit({"ok": True, "service": service, "count": len(store["services"])})
    return 0


def cmd_update(args):
    store = load_store(args.store)
    service = resolve(store, args.selector)
    changed = False
    if args.name is not None:
        new_name = args.name.strip()
        if ":" in new_name and args.issuer is None:
            new_issuer, new_name = (part.strip() for part in new_name.split(":", 1))
            service["issuer"] = new_issuer
        if new_name:
            service["name"] = new_name
            changed = True
    if args.issuer is not None:
        service["issuer"] = args.issuer.strip()
        changed = True
    if args.secret is not None:
        service["secret"] = clean_secret(args.secret)
        changed = True
    if args.digits is not None:
        service["digits"] = _int_or(args.digits, DEFAULT_DIGITS)
        changed = True
    if args.period is not None:
        service["period"] = _int_or(args.period, DEFAULT_PERIOD)
        changed = True
    if args.algorithm is not None:
        algorithm = args.algorithm.strip().upper()
        if algorithm not in ALGORITHMS:
            raise OtpError(f"algorithm must be one of {', '.join(ALGORITHMS)}")
        service["algorithm"] = algorithm
        changed = True
    if not changed:
        raise OtpError("nothing to change")
    save_store(args.store, store)
    emit({"ok": True, "service": service, "count": len(store["services"])})
    return 0


def cmd_remove(args):
    store = load_store(args.store)
    service = resolve(store, args.selector)
    store["services"] = [row for row in store["services"] if row["id"] != service["id"]]
    save_store(args.store, store)
    emit({"ok": True, "removed": _labelled(service["issuer"], service["name"]),
          "count": len(store["services"])})
    return 0


def entries_from_text(text):
    """Extract services from JSON exports or otpauth:// URI lists."""
    text = text.strip()
    if not text:
        raise OtpError("nothing to import")
    if "otpauth-migration://" in text:
        raise OtpError("Google Authenticator migration links are not supported; "
                       "export the accounts as otpauth:// URIs or JSON instead")

    entries = []
    document = None
    if text[0] in "{[":
        try:
            document = json.loads(text)
        except json.JSONDecodeError:
            document = None
    if document is not None:
        rows = document
        if isinstance(document, dict):
            rows = document.get("services")
            if not isinstance(rows, list):
                rows = document.get("entries")
            if not isinstance(rows, list):
                rows = [document]
        if not isinstance(rows, list):
            rows = [rows]
        for row in rows:
            entries.append(normalise_entry(row))
    else:
        for match in re.finditer(r"otpauth://[^\s\"'<>]+", text):
            try:
                entries.append(entry_from_uri(match.group(0)))
            except OtpError:
                entries.append(None)

    return [entry for entry in entries if entry]


def cmd_import(args):
    if args.path and args.path != "-":
        path = os.path.expanduser(args.path)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError as error:
            raise OtpError(f"cannot read {path}: {error}")
    else:
        text = sys.stdin.read()

    entries = entries_from_text(text)
    if not entries:
        raise OtpError("no TOTP accounts found in that file")

    store = load_store(args.store)
    added, skipped = [], 0
    for entry in entries:
        if any(same_service(existing, entry) for existing in store["services"]):
            skipped += 1
            continue
        if any(existing["id"] == entry["id"] for existing in store["services"]):
            entry["id"] = service_id(entry["issuer"], entry["name"], entry["secret"] + "!")
        store["services"].append(entry)
        added.append(_labelled(entry["issuer"], entry["name"]))
    if added:
        save_store(args.store, store)
    emit({"ok": True, "added": len(added), "skipped": skipped,
          "services": added, "count": len(store["services"])})
    return 0


def cmd_export(args):
    store = load_store(args.store)
    if not store["services"]:
        raise OtpError("there is nothing to export yet")
    if args.format == "uri":
        content = "\n".join(otpauth_uri(service) for service in store["services"]) + "\n"
    else:
        content = json.dumps(store, indent=2, ensure_ascii=False) + "\n"

    if not args.out or args.out == "-":
        sys.stdout.write(content)
        sys.stdout.flush()
        return 0

    path = os.path.expanduser(args.out)
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    descriptor, temp_path = tempfile.mkstemp(dir=directory, prefix=".authenticator-export-",
                                             suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(temp_path, 0o600)
        os.replace(temp_path, path)
    except BaseException:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise
    emit({"ok": True, "path": path, "format": args.format,
          "count": len(store["services"])})
    return 0


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def build_parser():
    parser = argparse.ArgumentParser(description="TOTP authenticator backend for ii")
    parser.add_argument("--store", default=DEFAULT_STORE,
                        help=f"service list JSON (default: {DEFAULT_STORE})")
    subparsers = parser.add_subparsers(dest="command", required=True)

    stream = subparsers.add_parser("stream", help="stream every code once per second")
    stream.set_defaults(func=cmd_stream)

    code = subparsers.add_parser("code", help="print one current code")
    code.add_argument("selector", help="service id or label")
    code.set_defaults(func=cmd_code)

    listing = subparsers.add_parser("list", help="print the stored services")
    listing.set_defaults(func=cmd_list)

    add = subparsers.add_parser("add", help="add a service")
    add.add_argument("secret")
    add.add_argument("--label", default="", help="'Issuer:account' or just 'account'")
    add.add_argument("--issuer", default="")
    add.add_argument("--name", default="")
    add.add_argument("--digits", default=None)
    add.add_argument("--period", default=None)
    add.add_argument("--algorithm", default=None)
    add.set_defaults(func=cmd_add)

    update = subparsers.add_parser("update", help="change a service")
    update.add_argument("selector", help="service id or label")
    update.add_argument("--name")
    update.add_argument("--issuer")
    update.add_argument("--secret")
    update.add_argument("--digits")
    update.add_argument("--period")
    update.add_argument("--algorithm")
    update.set_defaults(func=cmd_update)

    remove = subparsers.add_parser("remove", help="delete a service")
    remove.add_argument("selector", help="service id or label")
    remove.set_defaults(func=cmd_remove)

    importer = subparsers.add_parser("import", help="import JSON or otpauth:// URIs")
    importer.add_argument("path", nargs="?", default="-")
    importer.set_defaults(func=cmd_import)

    exporter = subparsers.add_parser("export", help="export services")
    exporter.add_argument("--format", choices=["json", "uri"], default="json")
    exporter.add_argument("--out", default="-")
    exporter.set_defaults(func=cmd_export)

    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.func(args) or 0
    except OtpError as error:
        return fail(str(error))
    except (KeyboardInterrupt, BrokenPipeError):
        return 0


if __name__ == "__main__":
    sys.exit(main())
