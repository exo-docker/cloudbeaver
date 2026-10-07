#!/bin/bash
# conf/cloudbeaver.conf is a modified copy of the cloudbeaver.conf shipped in the base image. When a new
# upstream version changes that file, our copy silently misses the new settings. This check fails in that
# case, so someone reviews the upstream change, ports what is needed to conf/cloudbeaver.conf and refreshes
# tests/upstream-cloudbeaver.conf.sha256 with the command printed below.
set -eu
cd "$(dirname "$0")/.."

BASE_IMAGE="$(sed -n 's/^FROM //p' Dockerfile | head -1)"
EXPECTED="$(cat tests/upstream-cloudbeaver.conf.sha256)"
ACTUAL="$(docker run --rm --entrypoint cat "${BASE_IMAGE}" /opt/cloudbeaver/conf/cloudbeaver.conf | sha256sum | cut -d' ' -f1)"

if [ "${EXPECTED}" != "${ACTUAL}" ]; then
  echo "The cloudbeaver.conf of ${BASE_IMAGE} changed since conf/cloudbeaver.conf was derived from it."
  echo "Review the upstream changes:"
  echo "  docker run --rm --entrypoint cat ${BASE_IMAGE} /opt/cloudbeaver/conf/cloudbeaver.conf | diff - conf/cloudbeaver.conf"
  echo "then port what is needed and refresh the reference with:"
  echo "  docker run --rm --entrypoint cat ${BASE_IMAGE} /opt/cloudbeaver/conf/cloudbeaver.conf | sha256sum | cut -d' ' -f1 > tests/upstream-cloudbeaver.conf.sha256"
  exit 1
fi
echo "Upstream cloudbeaver.conf of ${BASE_IMAGE} unchanged"
