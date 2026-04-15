#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8081}"
NEXUS_DATA="${NEXUS_DATA:-/nexus-data}"

mkdir -p "${NEXUS_DATA}/etc"

cat > "${NEXUS_DATA}/etc/nexus.properties" <<EOF
application-port=${PORT}
nexus-context-path=/
EOF

# Conservative JVM sizing for a constrained dyno.
# Increase carefully only if you move to a larger dyno and observe headroom.
export INSTALL4J_ADD_VM_PARAMS="${INSTALL4J_ADD_VM_PARAMS:--Xms512m -Xmx512m -XX:MaxDirectMemorySize=512m -Djava.util.prefs.userRoot=${NEXUS_DATA}/javaprefs}"

# Start Nexus in the background
/opt/sonatype/nexus/bin/nexus run &
NEXUS_PID=$!

# Best-effort: print the generated initial admin password into logs
# so you can recover it with `heroku logs --tail`.
for i in $(seq 1 180); do
  if [ -f "${NEXUS_DATA}/admin.password" ]; then
    echo "=================================================="
    echo "NEXUS INITIAL ADMIN PASSWORD:"
    cat "${NEXUS_DATA}/admin.password"
    echo "=================================================="
    break
  fi
  sleep 2
done

wait "${NEXUS_PID}"