#!/usr/bin/env bash
# Release the child distribution's own packages as .debs, on this machine:
#   1. bloom-release --no-pull-request into local release repositories;
#   2. their release stanzas in a working copy of this example's index;
#   3. ros_buildfarm's release jobs (source, then binary package) through
#      colcon-ros-buildfarm, for the child's packages only;
#   4. checks on the result and an install test in a clean container.
# Nothing is published: release repositories, index and apt repository all
# live in the work directory and are served on 127.0.0.1 during the run.
#
# Needs Linux x86_64 and the rootful Docker Engine at /var/run/docker.sock
# (ros_buildfarm runs linux/amd64 containers on the host network). Access to
# that socket is root on the host.
#
# Usage: tools/release_in_container.sh
# Environment: RELEASE_WORK_DIR (default: release-work in this example; must
# be empty or absent), RELEASE_GIT_PORT (default 19418), RELEASE_HTTP_PORT
# (default 18159), MAKEFLAGS (default -j2), RELEASE_STOP_AFTER (empty, or
# "prepare" to stop once the release stanzas are written).
set -euo pipefail
EXAMPLE_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$(cd "$EXAMPLE_DIR/../.." && pwd)
IMAGE=rep159-guide-release-runner
die() { echo "release_in_container: $*" >&2; exit 1; }

# Host requirements, checked before anything is created.
[ "$(id -u)" != 0 ] \
  || die "run it as your user, not as root: ros_buildfarm refuses uid 0 (add your user to the docker group instead of using sudo)"
[ "$(uname -s)" = Linux ] || die "needs Linux, found $(uname -s)"
[ "$(uname -m)" = x86_64 ] || die "needs an x86_64 host, found $(uname -m)"
[ -S /var/run/docker.sock ] || die "needs the Docker Engine socket at /var/run/docker.sock"
if [ -n "${DOCKER_HOST:-}" ] && [ "$DOCKER_HOST" != unix:///var/run/docker.sock ]; then
  die "needs the Docker Engine at /var/run/docker.sock, DOCKER_HOST is $DOCKER_HOST"
fi
endpoint=$(docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null) \
  || die "cannot read the current Docker context (DOCKER_CONTEXT=${DOCKER_CONTEXT:-default})"
[ "$endpoint" = unix:///var/run/docker.sock ] \
  || die "needs the Docker Engine at /var/run/docker.sock, the current context uses $endpoint (Docker Desktop is not supported)"
security=$(docker info -f '{{json .SecurityOptions}}' 2>/dev/null) \
  || die "cannot reach the Docker daemon at /var/run/docker.sock"
case $security in *rootless*) die "rootless Docker is not supported" ;; esac

WORK=$(realpath -m "${RELEASE_WORK_DIR:-$EXAMPLE_DIR/release-work}")
if [ -n "$(ls -A "$WORK" 2>/dev/null)" ]; then
  die "$WORK is not empty; move it away first: mv $WORK /tmp/"
fi

mkdir -p "$WORK/home"
echo "===== Runner image (the first build takes a few minutes)"
if ! docker build --progress=plain -f "$EXAMPLE_DIR/tools/release/Dockerfile" \
    -t "$IMAGE" "$REPO_ROOT" >"$WORK/runner-image.log" 2>&1; then
  tail -n 40 "$WORK/runner-image.log" >&2
  die "the runner image did not build; the whole output is in $WORK/runner-image.log"
fi

export WORK
export RELEASE_GIT_PORT=${RELEASE_GIT_PORT:-19418}
export RELEASE_HTTP_PORT=${RELEASE_HTTP_PORT:-18159}
export MAKEFLAGS=${MAKEFLAGS:--j2}
export RELEASE_STOP_AFTER=${RELEASE_STOP_AFTER:-}
# The work directory has the same path inside and out: the host's Docker
# daemon resolves the bind mounts of the job containers the runner starts.
# No credentials, SSH agent or git configuration go in. --init: Ctrl-C
# reaches the stage that is running (tini signals the whole process group);
# a job container that has already started can keep running to its end.
docker run --rm --init -e TINI_KILL_PROCESS_GROUP=1 --network host \
  --user "$(id -u):$(id -g)" --group-add "$(stat -c %g /var/run/docker.sock)" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$WORK:$WORK" -v "$EXAMPLE_DIR:/example:ro" \
  -e WORK -e HOME="$WORK/home" -e USER=rep159 -e LOGNAME=rep159 \
  -e MAKEFLAGS -e RELEASE_GIT_PORT -e RELEASE_HTTP_PORT -e RELEASE_STOP_AFTER \
  "$IMAGE" bash /example/tools/release/run_release.sh </dev/null
