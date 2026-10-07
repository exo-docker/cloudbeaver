#!/bin/bash
# Smoke test of the image: LDAP login, admin group binding, anonymous access, local auth, connections.
# Usage: tests/smoke.sh <image>
# Needs docker, jq and access to pull osixia/openldap. Everything runs on a throwaway docker network.
set -u

IMAGE="${1:?usage: $0 <image>}"
LDAP_IMAGE="osixia/openldap:1.5.0"
SUFFIX="$$"
NET="cbsmoke-${SUFFIX}"
LDAP="cbsmoke-ldap-${SUFFIX}"
CB="cbsmoke-cb-${SUFFIX}"
WORK="$(mktemp -d)"
FAILED=0

cleanup() {
  docker rm -f "${CB}" "${LDAP}" >/dev/null 2>&1
  docker network rm "${NET}" >/dev/null 2>&1
  rm -rf "${WORK}"
}
trap cleanup EXIT

pass() { echo "  ok   - $*"; }
fail() { echo "  FAIL - $*"; FAILED=1; }
check() { # description, expected, actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# Runs a graphql call against the server in a fresh session, prints the json answer.
# $1: query, $2: variables (json, default {}), $3: optional credentials json for the ldap provider
gql() {
  local jar="/tmp/jar.$RANDOM"
  docker exec "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d '{\"query\":\"mutation{ openSession{ valid } }\"}'" >/dev/null
  local body
  body="$(jq -nc --arg q "$1" --argjson v "${2:-{\}}" '{query:$q,variables:$v}')"
  printf '%s' "${body}" | docker exec -i "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d @-"
}

ldap_login() { # user password -> session stays in the same jar, so login and queries share one call
  local jar="/tmp/jar.$RANDOM" body out
  docker exec "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d '{\"query\":\"mutation{ openSession{ valid } }\"}'" >/dev/null
  body="$(jq -nc --arg u "$1" --arg p "$2" '{query:"query($c: Object){ authLogin(provider:\"ldap\", configuration:\"exo-ldap\", credentials:$c){ authStatus } }",variables:{c:{"user-dn":$u,password:$p}}}')"
  out="$(printf '%s' "${body}" | docker exec -i "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d @-")"
  LOGIN_STATUS="$(jq -r '.data.authLogin.authStatus // empty' <<<"${out}")"
  LOGIN_ERROR="$(jq -r '.errors[0].message // empty' <<<"${out}" | tr '\n' ' ')"
  SESSION_JAR="${jar}"
  sleep 1.5 # minimum delay between login attempts
}

session_query() { # graphql query in the session of the last ldap_login
  local body
  body="$(jq -nc --arg q "$1" '{query:$q}')"
  printf '%s' "${body}" | docker exec -i "${CB}" sh -c "curl -s -b ${SESSION_JAR} -c ${SESSION_JAR} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d @-"
}

echo "== Preparing LDAP and image ${IMAGE}"
docker network create "${NET}" >/dev/null || exit 2
docker run -d --name "${LDAP}" --network "${NET}" -e LDAP_ORGANISATION=eXo -e LDAP_DOMAIN=exo.test \
  -e LDAP_ADMIN_PASSWORD=admin "${LDAP_IMAGE}" >/dev/null || exit 2
for i in $(seq 1 60); do
  docker exec "${LDAP}" ldapsearch -x -H ldap://localhost -b dc=exo,dc=test -D cn=admin,dc=exo,dc=test -w admin >/dev/null 2>&1 && break
  sleep 2
done
# Same layout as the real directory: users with a cn based DN, groups elsewhere with a member attribute
docker exec -i "${LDAP}" ldapadd -x -D cn=admin,dc=exo,dc=test -w admin >/dev/null <<'LDIF' || exit 2
dn: ou=portal,dc=exo,dc=test
objectClass: organizationalUnit
ou: portal

dn: ou=users,ou=portal,dc=exo,dc=test
objectClass: organizationalUnit
ou: users

dn: cn=boss,ou=users,ou=portal,dc=exo,dc=test
objectClass: inetOrgPerson
cn: boss
sn: Boss
userPassword: Secret123

dn: cn=worker,ou=users,ou=portal,dc=exo,dc=test
objectClass: inetOrgPerson
cn: worker
sn: Worker
userPassword: Secret123

dn: ou=groups,dc=exo,dc=test
objectClass: organizationalUnit
ou: groups

dn: cn=cb-admins,ou=groups,dc=exo,dc=test
objectClass: groupOfNames
cn: cb-admins
member: cn=boss,ou=users,ou=portal,dc=exo,dc=test
LDIF

cat > "${WORK}/data-sources.json" <<'JSON'
{
  "folders": {},
  "connections": {
    "mysql-smoke": {
      "provider": "mysql",
      "driver": "mysql8",
      "name": "Smoke connection",
      "read-only": true,
      "configuration": {
        "host": "localhost", "port": "3306", "database": "none",
        "url": "jdbc:mysql://localhost:3306/none",
        "type": "dev", "auth-model": "native"
      }
    }
  }
}
JSON
chmod 666 "${WORK}/data-sources.json"

docker run -d --name "${CB}" --network "${NET}" \
  -v "${WORK}/data-sources.json:/opt/cloudbeaver/workspace/GlobalConfiguration/.dbeaver/data-sources.json" \
  -e CB_SERVER_NAME=smoke \
  -e CLOUDBEAVER_APP_GRANT_CONNECTIONS_ACCESS_TO_ANONYMOUS_TEAM=true \
  -e CLOUDBEAVER_LDAP_HOST="${LDAP}" \
  -e CLOUDBEAVER_LDAP_BASE_DN=dc=exo,dc=test \
  -e CLOUDBEAVER_LDAP_LOGIN_ATTR=cn \
  -e CLOUDBEAVER_LDAP_IDENTIFIER_ATTR=cn \
  -e CLOUDBEAVER_LDAP_BIND_USER=cn=admin,dc=exo,dc=test \
  -e CLOUDBEAVER_LDAP_BIND_PASSWORD=admin \
  -e CLOUDBEAVER_LDAP_ADMIN_GROUP=cn=cb-admins,ou=groups,dc=exo,dc=test \
  "${IMAGE}" >/dev/null || exit 2

abort() { # message: show the useful part of the container log and stop
  echo "  FAIL - $*"
  docker logs "${CB}" 2>&1 | grep -i "entrypoint\|ldap\|error\|exception" | tail -30
  echo "SMOKE TEST FAILED"
  exit 1
}

echo "== Waiting for the bootstrap (admin group binding, restart without local auth)"
ready=0
for i in $(seq 1 60); do
  docker logs "${CB}" 2>&1 | grep -q "restarting without the local auth provider" && { ready=1; break; }
  [ "$(docker inspect -f '{{.State.Running}}' "${CB}" 2>/dev/null)" = "true" ] || abort "the container stopped"
  sleep 2
done
[ "${ready}" -eq 1 ] || abort "the bootstrap did not complete within 2 minutes"
ready=0
for i in $(seq 1 45); do
  docker exec "${CB}" curl -sf localhost:8978/cloudbeaver/status >/dev/null 2>&1 && { ready=1; break; }
  sleep 2
done
[ "${ready}" -eq 1 ] || abort "the server did not come back after the restart"
sleep 5
docker logs "${CB}" 2>&1 | grep -q "Admin team bound to LDAP group" && pass "admin group bound" || fail "admin group binding not logged"

echo "== Checks"
out="$(gql '{ serverConfig { enabledAuthProviders anonymousAccessEnabled } }')"
check "only ldap is enabled" '["ldap"]' "$(jq -c '.data.serverConfig.enabledAuthProviders' <<<"${out}")"
check "anonymous access is disabled" "false" "$(jq -r '.data.serverConfig.anonymousAccessEnabled' <<<"${out}")"

out="$(gql '{ activeUser { userId } connections: userConnections { name } }')"
check "anonymous session has no user" "null" "$(jq -c '.data.activeUser' <<<"${out}")"

ldap_login boss Secret123
check "admin group member can log in" "SUCCESS" "${LOGIN_STATUS}"
out="$(session_query '{ activeUser { userId teams { teamId } } connections: userConnections { name } }')"
check "admin group member gets the admin team" "true" "$(jq -r '[.data.activeUser.teams[].teamId] | contains(["admin"])' <<<"${out}")"
check "admin sees the mounted connection" "Smoke connection" "$(jq -r '.data.connections[0].name' <<<"${out}")"

ldap_login worker Secret123
check "regular user can log in" "SUCCESS" "${LOGIN_STATUS}"
out="$(session_query '{ activeUser { userId teams { teamId } } connections: userConnections { name } }')"
check "regular user is not admin" "false" "$(jq -r '[.data.activeUser.teams[].teamId] | contains(["admin"])' <<<"${out}")"
check "regular user sees the mounted connection" "Smoke connection" "$(jq -r '.data.connections[0].name' <<<"${out}")"

ldap_login worker wrong-password
check "wrong password is refused" "" "${LOGIN_STATUS}"
case "${LOGIN_ERROR}" in *"Invalid Credentials"*) pass "wrong password reports an LDAP error";; *) fail "unexpected error for a wrong password: ${LOGIN_ERROR}";; esac

# local provider is gone: a login with it must be rejected as unsupported
jar="/tmp/jar.local"
docker exec "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d '{\"query\":\"mutation{ openSession{ valid } }\"}'" >/dev/null
out="$(docker exec "${CB}" sh -c "curl -s -b ${jar} -c ${jar} localhost:8978/cloudbeaver/api/gql -H 'content-type: application/json' -d '{\"query\":\"query{ authLogin(provider:\\\"local\\\", credentials:{user:\\\"cbadmin\\\",password:\\\"X\\\"}){ authStatus } }\"}'")"
case "$(jq -r '.errors[0].message // empty' <<<"${out}")" in
  *"Unsupported authentication provider"*) pass "local login is rejected";;
  *) fail "local login was not rejected: ${out}";;
esac

echo
if [ "${FAILED}" -eq 0 ]; then echo "SMOKE TEST PASSED"; else echo "SMOKE TEST FAILED"; docker logs "${CB}" 2>&1 | grep -i "entrypoint\|ldap\|error" | tail -30; fi
exit "${FAILED}"
