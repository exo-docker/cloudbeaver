#!/bin/bash
# Starts CloudBeaver and, once it is up, binds the Admin team to an LDAP group.
#
# CloudBeaver cannot declare this binding in its configuration files, it can only be set through the
# admin API. The built-in local admin (CB_ADMIN_NAME / CB_ADMIN_PASSWORD) is used once for that, then the
# server is restarted with the local auth provider removed so only LDAP remains.
#
# Env:
#   CLOUDBEAVER_LDAP_ADMIN_GROUP  Full DN of the LDAP group granted the Admin team (binding skipped if unset)
#   CLOUDBEAVER_LDAP_ENABLE_SSL   true to connect to LDAP over ldaps
#   CB_ADMIN_NAME                 Bootstrap admin user (default: cbadmin)
#   CB_ADMIN_PASSWORD             Bootstrap admin password (default: random, never shown)
set -u

CB_PORT="${CLOUDBEAVER_WEB_SERVER_PORT:-8978}"
CB_URL="http://localhost:${CB_PORT}${CLOUDBEAVER_ROOT_URI:-/cloudbeaver}"
RUNTIME_CONF="/opt/cloudbeaver/workspace/.data/.cloudbeaver.runtime.conf"
JAR="$(mktemp)"
SERVER_PID=""
STOPPING=0

log() { echo "[entrypoint] $*"; }

# The body goes through stdin so credentials never show up in the process list
gql() {
  printf '%s' "$1" | curl -fsS -b "${JAR}" -c "${JAR}" -H 'content-type: application/json' -d @- "${CB_URL}/api/gql"
}

bootstrap() {
  local i
  for i in $(seq 1 300); do
    [ "${STOPPING}" -eq 1 ] && return 1
    curl -fs "${CB_URL}/status" >/dev/null 2>&1 && break
    sleep 1
  done

  gql '{"query":"mutation{ openSession{ valid } }"}' >/dev/null || { log "cannot open session, skipping LDAP admin binding"; return 1; }

  local hash out
  hash="$(printf '%s' "${CB_ADMIN_PASSWORD}" | md5sum | cut -d' ' -f1 | tr 'a-f' 'A-F')"
  out="$(gql "{\"query\":\"query{ authLogin(provider:\\\"local\\\", credentials:{user:\\\"${CB_ADMIN_NAME}\\\",password:\\\"${hash}\\\"}){ authStatus } }\"}" 2>&1)"
  unset hash
  if ! grep -q '"SUCCESS"' <<<"${out}"; then
    log "local admin login failed, assuming the instance is already bootstrapped"
    return 1
  fi

  out="$(gql "$(jq -nc --arg g "${CLOUDBEAVER_LDAP_ADMIN_GROUP}" \
    '{query:"query($p: Object!){ setTeamMetaParameterValues(teamId:\"admin\", parameters:$p) }",variables:{p:{"ldap.group-name":$g}}}')" 2>&1)"
  if grep -Eq '"setTeamMetaParameterValues": *true' <<<"${out}"; then
    log "Admin team bound to LDAP group ${CLOUDBEAVER_LDAP_ADMIN_GROUP}"
    return 0
  fi
  log "failed to bind Admin team: $(tr -d '\n' <<<"${out}")"
  return 1
}

start_server() {
  ./launch-product.sh "$@" &
  SERVER_PID=$!
}


stop_server() {
  kill -TERM "${SERVER_PID}" 2>/dev/null
  wait "${SERVER_PID}" 2>/dev/null
}

# Removes the local provider from the runtime configuration, which takes precedence over conf/
disable_local_auth() {
  # Rewritten in place so the file keeps its owner (the server runs as the dbeaver user)
  local tmp
  tmp="$(mktemp)"
  sed '/"enabledAuthProviders"/,/\]/{/"local"/d}' "${RUNTIME_CONF}" > "${tmp}" && cat "${tmp}" > "${RUNTIME_CONF}"
  rm -f "${tmp}"
}

# The LDAP provider needs a real boolean, which an env placeholder cannot produce (it always yields a string)
if [ "${CLOUDBEAVER_LDAP_ENABLE_SSL:-false}" = "true" ]; then
  sed -i 's/ldap-enable-ssl: false/ldap-enable-ssl: true/' conf/cloudbeaver.conf
fi

export CB_ADMIN_NAME="${CB_ADMIN_NAME:-cbadmin}"
if [ -z "${CB_ADMIN_PASSWORD:-}" ]; then
  # Prefix satisfies the default password policy (mixed case + digit)
  CB_ADMIN_PASSWORD="Aa1$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
export CB_ADMIN_PASSWORD

trap 'STOPPING=1; kill -TERM "${SERVER_PID}" 2>/dev/null' TERM INT

start_server "$@"

if [ -n "${CLOUDBEAVER_LDAP_ADMIN_GROUP:-}" ] && bootstrap && [ "${STOPPING}" -eq 0 ]; then
  log "restarting without the local auth provider"
  stop_server
  disable_local_auth
  # The bootstrap admin is only needed to create the first admin, the restarted server must not inherit it
  unset CB_ADMIN_NAME CB_ADMIN_PASSWORD
  [ "${STOPPING}" -eq 0 ] && start_server "$@"
fi
unset CB_ADMIN_NAME CB_ADMIN_PASSWORD

wait "${SERVER_PID}"
