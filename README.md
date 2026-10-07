# CloudBeaver eXo image

`dbeaver/cloudbeaver` plus a minimal configuration (no pre-built workspace): LDAP-only login, no anonymous access,
no custom connections. The first-run wizard is skipped by the `CB_*` variables.

Connections are provided by mounting a `data-sources.json` on
`/opt/cloudbeaver/workspace/GlobalConfiguration/.dbeaver/data-sources.json`.
Set `CLOUDBEAVER_APP_GRANT_CONNECTIONS_ACCESS_TO_ANONYMOUS_TEAM=true` so every logged-in user sees them.

| Variable | Purpose |
|---|---|
| `CB_SERVER_NAME` | Server name (skips the setup wizard) |
| `CB_ADMIN_NAME` / `CB_ADMIN_PASSWORD` | Bootstrap local admin, only usable during startup (default `cbadmin` / random, discarded) |
| `CLOUDBEAVER_LDAP_HOST`, `_PORT`, `_ENABLE_SSL` | LDAP server (`_ENABLE_SSL=true` for ldaps) |
| `CLOUDBEAVER_LDAP_BASE_DN` | Search base, must also contain the groups |
| `CLOUDBEAVER_LDAP_BIND_USER`, `_BIND_PASSWORD` | Service account used to search users and groups |
| `CLOUDBEAVER_LDAP_LOGIN_ATTR` | Attribute users log in with (e.g. `uid`) |
| `CLOUDBEAVER_LDAP_ADMIN_GROUP` | Full DN of the LDAP group that gets the Admin team |
| `CLOUDBEAVER_AI_CHAT_DISABLED` | Disable the AI assistant |

The group binding cannot be declared in CloudBeaver config files, so `entrypoint.sh` sets it through the admin API on
startup using the bootstrap admin, then restarts the server once with the `local` auth provider removed, so only LDAP
remains (first start takes about twice as long). Groups are matched by full DN through the `member` attribute.

## Tags and releases
- Version tags are `<upstream version>-<revision>`, e.g. `26.2.2-0`: the upstream CloudBeaver version the image is
  based on, then our own revision, starting at `0`. They are immutable. `latest` follows `master`.
- A new upstream version is picked up nightly by `build.yml`, which bumps the `FROM`, and tags `<new version>-0`.
- A change on our side only (conf, entrypoint) is released by hand with the next revision:
  `git tag 26.2.2-1 && git push origin 26.2.2-1`.
- The previous tags without a revision (e.g. `26.2.2`) are the old workspace based images and are not updated.

## Tests
`tests/smoke.sh <image>` starts the image next to a throwaway OpenLDAP and checks the LDAP login, the admin group
binding, that anonymous and local access are refused and that connections are visible. It runs on every pull
request and **before every publication** (`publish.yml`), so a breaking change, including one coming from a new
upstream version, stops the release instead of reaching users.
`tests/check-upstream-conf.sh` fails when the `cloudbeaver.conf` of the base image changed, because our
`conf/cloudbeaver.conf` is a modified copy of it. It prints the commands to review the change and refresh
`tests/upstream-cloudbeaver.conf.sha256`.

```
docker build -t cloudbeaver-test . && tests/smoke.sh cloudbeaver-test
```
