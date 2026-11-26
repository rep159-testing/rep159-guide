#!/usr/bin/env bash
# The stages of tools/release_in_container.sh; runs inside the runner image
# (tools/release/Dockerfile) as the host user, with WORK at the same path as
# on the host. Every command that could ask a question reads /dev/null.
set -euo pipefail
: "${WORK:?}" "${RELEASE_GIT_PORT:?}" "${RELEASE_HTTP_PORT:?}" "${MAKEFLAGS:?}"
TOOLS=/example/tools/release
RT=(python3 "$TOOLS/release_tools.py")
WS=/opt/rep159_ws/src/tools
DISTRO=$(python3 -c "import yaml; print(yaml.safe_load(open('$TOOLS/releases.yaml'))['distro'])")
REPOS=$(python3 -c "import yaml; print(' '.join(yaml.safe_load(open('$TOOLS/releases.yaml'))['repositories']))")
DIST_FILE=$WORK/index/$DISTRO/distribution.yaml
GIT_URL=git://127.0.0.1:$RELEASE_GIT_PORT
declare -A VERSIONS

PIDS=()
cleanup() { for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
stage() { echo; echo "===== $*"; }
die() { echo "run_release: $*" >&2; exit 1; }
pinned_version() {
  python3 -c "import yaml, sys; print(yaml.safe_load(open('$TOOLS/releases.yaml'))['repositories']['$1'].get('version', ''))"
}

preflight_ports() {
  stage "Local ports"
  local var
  # SO_REUSEADDR, as both servers use: connections of an earlier run left
  # in TIME_WAIT do not count, a listening socket does.
  for var in RELEASE_GIT_PORT RELEASE_HTTP_PORT; do
    python3 -c "
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1])))
s.listen()" "${!var}" 2>/dev/null || die "port ${!var} ($var) is in use"
  done
}

stage_index() {
  stage "Working index in $WORK/index"
  "${RT[@]}" prepare-index /example "$WORK/index" --git-base "$GIT_URL"
  local repo
  for repo in $REPOS; do
    git init -q --bare --initial-branch=master "$WORK/git/$repo-release.git"
  done
}

stage_servers() {
  stage "git daemon on 127.0.0.1:$RELEASE_GIT_PORT, http.server on 127.0.0.1:$RELEASE_HTTP_PORT"
  git daemon --reuseaddr --listen=127.0.0.1 --port="$RELEASE_GIT_PORT" \
    --base-path="$WORK/git" --export-all >"$WORK/git-daemon.log" 2>&1 &
  PIDS+=($!)
  python3 -m http.server --bind 127.0.0.1 "$RELEASE_HTTP_PORT" \
    --directory "$WORK" >"$WORK/http-server.log" 2>&1 &
  PIDS+=($!)
  export ROSDISTRO_INDEX_URL=http://127.0.0.1:$RELEASE_HTTP_PORT/index/index-v4.yaml
  local i first=${REPOS%% *}
  for i in $(seq 50); do
    if git ls-remote "$GIT_URL/$first-release.git" >/dev/null 2>&1 </dev/null \
        && curl -fs "$ROSDISTRO_INDEX_URL" >/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  die "the local servers did not answer within 10 s (see $WORK/*.log)"
}

stage_git_safety() {
  stage "git identity, and no pushes to GitHub"
  git config --global user.name 'rep159-guide example'
  git config --global user.email rep159-guide@example.invalid
  git config --global url.file:///nonexistent/github/.pushInsteadOf https://github.com/
  git config --global --add url.file:///nonexistent/github/.pushInsteadOf git@github.com:
  # The image's checkouts belong to root; a local clone checks the .git path.
  local repo
  for repo in ros_buildfarm rosdistro; do
    git config --global --add safe.directory "$WS/$repo"
    git config --global --add safe.directory "$WS/$repo/.git"
  done
}

stage_rosdep() {
  stage "rosdep from the working index"
  # rosdep gives up on a download after 15 s, and GitHub can be slower than
  # that. Fetch its rules with curl instead and point rosdep at the copies:
  # base.yaml and python.yaml hold every system dependency of this example.
  local rules=https://raw.githubusercontent.com/ros/rosdistro/master/rosdep f
  mkdir -p "$WORK/rosdep/sources.list.d"
  for f in base.yaml python.yaml; do
    curl -fsSL --retry 5 --retry-all-errors --max-time 300 \
      -o "$WORK/rosdep/$f" "$rules/$f" || die "cannot fetch $rules/$f"
    echo "yaml file://$WORK/rosdep/$f" >>"$WORK/rosdep/sources.list.d/20-local.list"
  done
  export ROSDEP_SOURCE_PATH=$WORK/rosdep/sources.list.d
  # The parent's index still comes from GitHub, through rosdistro.
  local attempt
  for attempt in 1 2 3; do
    rosdep update --rosdistro "$DISTRO" </dev/null && break
    [ "$attempt" = 3 ] && die "rosdep update failed 3 times"
    sleep 10
  done
  local got
  got=$(rosdep resolve geometry_msgs --rosdistro "$DISTRO" </dev/null | tail -n 1)
  [ "$got" = ros-lyrical-geometry-msgs ] \
    || die "rosdep resolves geometry_msgs to '$got', expected ros-lyrical-geometry-msgs"
}

stage_ros_buildfarm_branch() {
  # The release jobs clone the ros_buildfarm checkout that generated them
  # (its origin URL and branch) and run its scripts with that clone first on
  # PYTHONPATH. A rosdistro/ at the root of the clone therefore wins over the
  # python3-rosdistro-modules the job images install from apt.
  stage "ros_buildfarm branch with the REP 159 rosdistro"
  local sha
  sha=$(git -C "$WS/rosdistro" rev-parse --short HEAD)
  git clone -q "$WS/ros_buildfarm" "$WORK/ros_buildfarm" </dev/null
  git -C "$WORK/ros_buildfarm" checkout -q -b rep159-guide-local
  cp -r "$WS/rosdistro/src/rosdistro" "$WORK/ros_buildfarm/rosdistro"
  git -C "$WORK/ros_buildfarm" add rosdistro
  git -C "$WORK/ros_buildfarm" commit -q \
    -m "Vendor the REP 159 rosdistro $sha (rep159-guide example, local only)" \
    -m "The release jobs run ros_buildfarm's scripts with this checkout first on PYTHONPATH, so they import this rosdistro instead of the stock one. Never pushed."
  git clone -q --bare "$WORK/ros_buildfarm" "$WORK/git/ros_buildfarm.git" </dev/null
  git -C "$WORK/ros_buildfarm" remote set-url origin "$GIT_URL/ros_buildfarm.git"
  export PYTHONPATH=$WORK/ros_buildfarm${PYTHONPATH:+:$PYTHONPATH}
  python3 -c 'import ros_buildfarm, rosdistro; print("ros_buildfarm:", ros_buildfarm.__file__); print("rosdistro:", rosdistro.__file__)'
}

stage_bloom() {
  local repo bare tmp version pinned
  mkdir -p "$WORK/tmp"
  for repo in $REPOS; do
    stage "bloom-release $repo"
    bare=$WORK/git/$repo-release.git
    tmp=$WORK/tmp/$repo-tracks
    # bloom's track creation prompts even with --non-interactive: write it.
    git clone -q "$bare" "$tmp" </dev/null 2>/dev/null
    "${RT[@]}" tracks "$DIST_FILE" "$repo" --push-url "file://$bare" >"$tmp/tracks.yaml"
    git -C "$tmp" add tracks.yaml
    git -C "$tmp" commit -q -m "Track $DISTRO (rep159-guide example)"
    git -C "$tmp" push -q origin master </dev/null
    (cd "$WORK/tmp" && bloom-release "$repo" --rosdistro "$DISTRO" --track "$DISTRO" \
      --non-interactive --no-pull-request --no-web \
      --override-release-repository-url "$GIT_URL/$repo-release.git" \
      --override-release-repository-push-url "file://$bare" </dev/null)
    version=$(git --git-dir "$bare" tag -l "release/$DISTRO/*" \
      | "${RT[@]}" release-version --package "$repo") \
      || die "bloom left no single release/$DISTRO/$repo/* tag in $bare"
    pinned=$(pinned_version "$repo")
    if [ -n "$pinned" ] && [ "$version" != "$pinned" ]; then
      die "$repo released as $version, releases.yaml pins $pinned: $repo changed upstream; update releases.yaml"
    fi
    VERSIONS[$repo]=$version
    echo "$repo: $version"
  done
}

stage_stanzas_and_cache() {
  stage "Release stanzas and cache"
  local repo
  for repo in $REPOS; do
    # The pinned ones (the workspace package) got theirs before bloom ran.
    [ -n "$(pinned_version "$repo")" ] && continue
    "${RT[@]}" add-stanza "$DIST_FILE" "$repo" \
      --url "$GIT_URL/$repo-release.git" --version "${VERSIONS[$repo]}"
  done
  (cd "$WORK/index" \
    && python3 -m rosdistro.cli.rosdistro_build_cache --preclean --include-source \
      index-v4.yaml "$DISTRO" </dev/null \
    && gzip -n -9 -c "$DISTRO-cache.yaml" >"$DISTRO-cache.yaml.gz")
  python3 /example/tools/check_extension.py "$ROSDISTRO_INDEX_URL" "$DISTRO" \
    --expect-from-parent rclcpp geometry_msgs
  if [ "${RELEASE_STOP_AFTER:-}" = prepare ]; then
    stage "Stopping after the prepare stages (RELEASE_STOP_AFTER=prepare)"
    exit 0
  fi
}

stage_buildfarm() {
  stage "ros_buildfarm release jobs through colcon-ros-buildfarm"
  mkdir -p "$WORK/config"
  # ros_buildfarm writes the key into its Dockerfiles: the armored ros.asc.
  curl -fsSL --retry 5 --retry-all-errors --max-time 300 \
    -o "$WORK/config/ros.asc" https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc
  "${RT[@]}" buildfarm-config "$WORK/config" --index-url "$ROSDISTRO_INDEX_URL" \
    --ros-key "$WORK/config/ros.asc" --makeflags="$MAKEFLAGS"
  # colcon-ros-distro discovers the child's own packages only; the job
  # scripts clone the local ros_buildfarm branch (origin of $WORK/ros_buildfarm).
  (cd "$WORK" && ros_buildfarm release \
    --build-base "$WORK/buildfarm" --repo-base "$WORK/repo" \
    --config-url "http://127.0.0.1:$RELEASE_HTTP_PORT/config/index.yaml" \
    --build-name default --target-platform ubuntu:resolute:amd64 \
    --ros-distro "$DISTRO" --executor sequential </dev/null) \
    | tee "$WORK/buildfarm.log"
  # colcon-ros-distro logs this at INFO, which only colcon's log files keep.
  local skipped
  skipped=$(grep -rhos "Skipping [0-9]* repositories that '$DISTRO' takes from 'lyrical' as binaries" \
    "$WORK/log" | sort -u)
  [ -n "$skipped" ] \
    || die "colcon-ros-distro did not report skipping the lyrical repositories"
  echo "colcon-ros-distro: $skipped"
  grep -q "Summary: 3 packages finished" "$WORK/buildfarm.log" \
    || die "colcon-ros-buildfarm did not finish exactly 3 packages"
}

stage_verify() {
  stage "Checks on the built packages"
  "${RT[@]}" verify-pool "$WORK/repo"
  "${RT[@]}" verify-debs "$WORK/repo"
  local logs
  logs=$(grep -rl 'Vendor the REP 159 rosdistro' "$WORK/log" | wc -l)
  [ "$logs" -ge 3 ] \
    || die "only $logs job logs show the vendored rosdistro commit, expected one per package"
  local where
  where=$(docker run --rm --entrypoint python3 -e PYTHONPATH=/tmp/ros_buildfarm \
    -v "$WORK/ros_buildfarm:/tmp/ros_buildfarm:ro" \
    "sourcedeb.${DISTRO}_ubuntu_resolute_ros_workspace" \
    -c 'import rosdistro; print(rosdistro.__file__)' </dev/null)
  [ "$where" = /tmp/ros_buildfarm/rosdistro/__init__.py ] \
    || die "the source job image imports rosdistro from $where"
  echo "job logs with the vendored rosdistro: $logs; source job image imports $where"
}

stage_smoke() {
  stage "Install test in a clean ubuntu:resolute"
  # /example is this container's own mount, which the host daemon cannot
  # see; $WORK has the same path on both sides.
  cp "$TOOLS/smoke_install.sh" "$WORK/smoke_install.sh"
  docker run --rm -v "$WORK:$WORK:ro" ubuntu:resolute \
    bash "$WORK/smoke_install.sh" "$WORK/repo" </dev/null
}

preflight_ports
stage_index
stage_servers
stage_git_safety
stage_rosdep
stage_ros_buildfarm_branch
stage_bloom
stage_stanzas_and_cache
stage_buildfarm
stage_verify
stage_smoke
stage "Done"
find "$WORK/repo" -name '*.deb' | sort
echo RELEASE-OK
