#!/usr/bin/env bash
# Adversarial health check for grok-mcp-server. Proves the static auth path and,
# with CONNECT_SECRET, the connector flow. Unauthenticated requests are REFUSED.
# An open endpoint here bills your xAI account, so "open" is a hard failure,
# never a warning.
#
#   AUTH_SECRET=... CONNECT_SECRET=... ./verify.sh
#   MCP_URL=https://your-worker.your-subdomain.workers.dev AUTH_SECRET=... CONNECT_SECRET=... ./verify.sh
#
# Secrets are read from the environment on purpose. Never hardcode them: this
# file is committed. Without CONNECT_SECRET, path B asserts a disabled flow (503).

set -uo pipefail

URL="${MCP_URL:-https://<your-worker>.<your-subdomain>.workers.dev}"
SECRET="${AUTH_SECRET:-}"
CONNECT="${CONNECT_SECRET:-}"
EXPECTED_TOOLS="${EXPECTED_TOOLS:-9}"
fail=0
p(){ printf '%-38s %s\n' "$1" "$2"; }

if [ -z "$SECRET" ]; then
  echo "AUTH_SECRET is not set. Export it and re-run." >&2
  exit 2
fi

# Secrets travel to curl through a config on stdin, never on its command line,
# where any local process could read them.
cfg_quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

count_tools() {
  # $1 = bearer token. Stateless transport: tools/list needs no initialize and
  # no session id. Accept either JSON or SSE data lines.
  printf 'header = "authorization: Bearer %s"\n' "$(cfg_quote "$1")" |
  curl -s -m 25 --config - -X POST "$URL/mcp" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
    | python3 -c 'import json,sys
body = sys.stdin.read()
try:
    try: messages = [json.loads(body)]
    except ValueError:
        messages = [json.loads(line[5:].strip()) for line in body.splitlines() if line.startswith("data:")]
    print(next(len(msg["result"]["tools"]) for msg in messages if "tools" in msg.get("result", {})))
except Exception: print(0)' 2>/dev/null
}

http() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@"; }

json_field() {
  python3 -c 'import json,sys
try: print(json.load(sys.stdin).get(sys.argv[1], ""))
except Exception: print("")' "$1" 2>/dev/null
}

exchange_code() {
  curl -s -m 15 -X POST "$URL/oauth/token" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "code=$CODE" \
    --data-urlencode "redirect_uri=https://claude.ai/api/mcp/auth_callback" \
    --data-urlencode "code_verifier=$1"
}

# ── Path A: static AUTH_SECRET bearer (headless automation, Claude Code) ───────
n=$(count_tools "$SECRET")
if [ "${n:-0}" -eq "$EXPECTED_TOOLS" ]; then p "A: static bearer → tools/list" "ok ($n tools)"
else p "A: static bearer" "FAIL (got $n, expected $EXPECTED_TOOLS)"; fail=1; fi

# ── Auth gate: no request should ever reach tools/list unauthenticated ────────
c=$(http -X POST "$URL/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
if [ "$c" = "401" ]; then p "no credential" "ok (401)"
else p "no credential" "FAIL ($c: ENDPOINT IS OPEN)"; fail=1; fi

c=$(http -X POST "$URL/mcp" -H 'authorization: Bearer wrong' -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
if [ "$c" = "401" ]; then p "bad credential" "ok (401)"
else p "bad credential" "FAIL ($c, expected 401)"; fail=1; fi

# ── Path B: full OAuth 2.0 / PKCE (the claude.ai connector) ────────────────────
c=$(http "$URL/.well-known/oauth-authorization-server")
if [ "$c" = "200" ]; then p "oauth discovery" "ok (200)"
else p "oauth discovery" "FAIL ($c)"; fail=1; fi

if [ -z "$CONNECT" ]; then
  # Without the key this run cannot mint a code. It still proves nobody else can:
  # 503 means the connector flow is off, 401 means it is on and demands the key.
  p "B: OAuth/PKCE" "skipped (set CONNECT_SECRET to test the connector flow)"
  c=$(http -X POST "$URL/oauth/confirm" -H 'content-type: application/x-www-form-urlencoded')
  if [ "$c" = "503" ]; then p "B: connector flow off" "ok (503)"
  elif [ "$c" = "401" ]; then p "B: connector demands the key" "ok (401)"
  else p "B: confirm without key" "FAIL ($c, expected 503 or 401)"; fail=1; fi
else
  VER=$(openssl rand -hex 32)
  CH=$(printf '%s' "$VER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')

  c=$(http -X POST "$URL/oauth/confirm" -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "connect_key=wrong" \
    --data-urlencode "redirect_uri=https://claude.ai/api/mcp/auth_callback" \
    --data-urlencode "state=xyz" --data-urlencode "code_challenge=$CH")
  if [ "$c" = "401" ]; then p "B: wrong connect key rejected" "ok (401)"
  else p "B: wrong connect key" "FAIL ($c, expected 401)"; fail=1; fi

  LOC=$(printf 'data-urlencode = "connect_key=%s"\n' "$(cfg_quote "$CONNECT")" |
    curl -s -m 15 --config - -o /dev/null -w '%{redirect_url}' -X POST "$URL/oauth/confirm" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode "redirect_uri=https://claude.ai/api/mcp/auth_callback" \
    --data-urlencode "state=xyz" --data-urlencode "code_challenge=$CH")
  CODE=$(printf '%s' "$LOC" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')

  # Check PKCE before redemption so a spent code cannot mask a verifier failure.
  err=$(exchange_code WRONG | json_field error)
  if [ "$err" = "invalid_grant" ]; then p "B: wrong PKCE rejected" "ok (invalid_grant)"
  else p "B: PKCE negative" "FAIL (expected invalid_grant)"; fail=1; fi

  TOK=$(exchange_code "$VER" | json_field access_token)
  if [ -n "$TOK" ]; then p "B: OAuth/PKCE → token" "ok"
  else p "B: token exchange" "FAIL"; fail=1; fi

  n=$(count_tools "$TOK")
  if [ "${n:-0}" -eq "$EXPECTED_TOOLS" ]; then p "B: oauth token → tools/list" "ok ($n tools)"
  else p "B: oauth token" "FAIL (got $n)"; fail=1; fi

  err=$(exchange_code "$VER" | json_field error)
  if [ "$err" = "invalid_grant" ]; then p "B: code replay rejected" "ok (invalid_grant)"
  else p "B: code replay" "FAIL (expected invalid_grant)"; fail=1; fi
fi

echo
[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
