#!/bin/sh
set -eu

PORT="${PORT:-8081}"
NEXUS_DATA="${NEXUS_DATA:-/nexus-data}"
BASE_URL="http://127.0.0.1:${PORT}"
ADMIN_USER="admin"

mkdir -p "${NEXUS_DATA}/etc"

cat > "${NEXUS_DATA}/etc/nexus.properties" <<EOF
application-port=${PORT}
nexus-context-path=/
EOF

export INSTALL4J_ADD_VM_PARAMS="${INSTALL4J_ADD_VM_PARAMS:--Xms128m -Xmx384m -XX:MaxDirectMemorySize=128m -Djava.util.prefs.userRoot=${NEXUS_DATA}/javaprefs}"

/opt/sonatype/nexus/bin/nexus run &
NEXUS_PID=$!

log() {
  echo "[bootstrap] $*"
}

wait_for_file() {
  file="$1"
  i=0
  while [ "$i" -lt 300 ]; do
    if [ -f "$file" ]; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

wait_for_http() {
  i=0
  while [ "$i" -lt 300 ]; do
    if curl -fsS "${BASE_URL}/service/rest/v1/status/check" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

nexus_api() {
  method="$1"
  path="$2"
  body="${3:-}"
  content_type="${4:-application/json}"

  if [ -n "$body" ]; then
    curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
      -X "$method" \
      -H "Content-Type: ${content_type}" \
      -d "$body" \
      "${BASE_URL}${path}"
  else
    curl -fsS -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
      -X "$method" \
      "${BASE_URL}${path}"
  fi
}

escape_json() {
  # minimal escaping for quotes and backslashes
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bootstrap_nexus() {
  if [ -z "${NEXUS_ADMIN_PASSWORD:-}" ]; then
    log "NEXUS_ADMIN_PASSWORD is not set; skipping bootstrap"
    return 0
  fi

  if ! wait_for_file "${NEXUS_DATA}/admin.password"; then
    log "Timed out waiting for ${NEXUS_DATA}/admin.password"
    return 1
  fi

  INITIAL_ADMIN_PASSWORD="$(cat "${NEXUS_DATA}/admin.password" | tr -d '\r\n')"
  log "Initial admin password file detected"

  if ! wait_for_http; then
    log "Timed out waiting for Nexus HTTP endpoint"
    return 1
  fi

  # Prefer the configured admin password first in case bootstrap already ran once.
  if curl -fsS -u "${ADMIN_USER}:${NEXUS_ADMIN_PASSWORD}" \
      "${BASE_URL}/service/rest/v1/security/users" >/dev/null 2>&1; then
    ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD}"
    log "Admin password already set"
  else
    ADMIN_PASSWORD="${INITIAL_ADMIN_PASSWORD}"
    log "Changing admin password"
    nexus_api PUT "/service/rest/v1/security/users/admin/change-password" \
      "${NEXUS_ADMIN_PASSWORD}" \
      "text/plain" >/dev/null
    ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD}"
    log "Admin password changed"
  fi

  # Create or update the proxy user.
  if [ -n "${NEXUS_PROXY_USER:-}" ] && [ -n "${NEXUS_PROXY_PASSWORD:-}" ]; then
    if nexus_api GET "/service/rest/v1/security/users?userId=${NEXUS_PROXY_USER}" >/tmp/nexus-users.json 2>/dev/null && \
       grep -q "\"userId\":\"${NEXUS_PROXY_USER}\"" /tmp/nexus-users.json; then
      log "Proxy user already exists; updating password"
      nexus_api PUT "/service/rest/v1/security/users/${NEXUS_PROXY_USER}/change-password" \
        "${NEXUS_PROXY_PASSWORD}" \
        "text/plain" >/dev/null
    else
      log "Creating proxy user"
      FIRSTNAME_ESCAPED="$(escape_json "${NEXUS_PROXY_FIRSTNAME:-Build}")"
      LASTNAME_ESCAPED="$(escape_json "${NEXUS_PROXY_LASTNAME:-Proxy}")"
      EMAIL_ESCAPED="$(escape_json "${NEXUS_PROXY_EMAIL:-buildproxy@example.invalid}")"
      USER_ESCAPED="$(escape_json "${NEXUS_PROXY_USER}")"
      PASS_ESCAPED="$(escape_json "${NEXUS_PROXY_PASSWORD}")"

      nexus_api POST "/service/rest/v1/security/users" "$(cat <<EOF
{
  "userId": "${USER_ESCAPED}",
  "firstName": "${FIRSTNAME_ESCAPED}",
  "lastName": "${LASTNAME_ESCAPED}",
  "emailAddress": "${EMAIL_ESCAPED}",
  "password": "${PASS_ESCAPED}",
  "status": "active",
  "roles": ["nx-anonymous"]
}
EOF
)" "application/json" >/dev/null
    fi
  else
    log "Proxy user vars not fully set; skipping proxy user creation"
  fi

  log "Disabling anonymous access"
  nexus_api PUT "/service/rest/v1/security/anonymous" \
    '{"enabled":false,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
    "application/json" >/dev/null

  log "Bootstrap complete"
}

bootstrap_nexus || log "Bootstrap failed; Nexus will keep running"

wait "${NEXUS_PID}"