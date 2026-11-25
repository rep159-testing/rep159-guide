#!/usr/bin/env bash
# Build and test the child distribution's own packages against the official
# Lyrical binaries, in a clean Ubuntu resolute container:
#   1. ROS 2 apt repository (packages.ros.org) and the REP 159 rosdistro and
#      rosdep, pip-installed over the stock ones;
#   2. rosdep initialised from this example's index (ROSDISTRO_INDEX_URL);
#   3. the child's own repositories, from its distribution file;
#   4. rosdep install: their ROS dependencies resolve to ros-lyrical-* debs;
#   5. colcon build and test on top of /opt/ros/lyrical.
#
# Usage: tools/build_in_container.sh [DISTRO]   (default: my-extended-distro)
# Environment: ROSDISTRO_REF, ROSDEP_REF (branch or commit of the
# rep159-testing forks; defaults: the branches in rep159.repos), MAKEFLAGS
# (default -j2), DOCKER_MEMORY (default 6g).
set -euo pipefail
EXAMPLE_DIR=$(cd "$(dirname "$0")/.." && pwd)
DISTRO=${1:-my-extended-distro}
ROSDISTRO_REF=${ROSDISTRO_REF:-feat/rep159-workspace-package}
ROSDEP_REF=${ROSDEP_REF:-feat/rep159-binary-lookup}

docker run --rm --memory "${DOCKER_MEMORY:-6g}" \
  -v "$EXAMPLE_DIR:/example:ro" \
  -e DISTRO="$DISTRO" -e ROSDISTRO_REF="$ROSDISTRO_REF" -e ROSDEP_REF="$ROSDEP_REF" \
  -e MAKEFLAGS="${MAKEFLAGS:--j2}" \
  -e DEBIAN_FRONTEND=noninteractive \
  ubuntu:resolute bash -euo pipefail -c '
step() { echo; echo "===== $*"; }

step "ROS 2 apt repository and tools"
apt-get update -qq
apt-get install -qq -y --no-install-recommends ca-certificates curl gnupg >/dev/null
curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu resolute main" \
  > /etc/apt/sources.list.d/ros2.list
apt-get update -qq
apt-get install -qq -y --no-install-recommends build-essential cmake git \
  python3-pip python3-rosdep python3-vcstool python3-colcon-common-extensions >/dev/null

step "REP 159 rosdistro ${ROSDISTRO_REF} and rosdep ${ROSDEP_REF} over the stock ones"
pip3 install -q --break-system-packages --no-deps \
  "git+https://github.com/rep159-testing/rosdistro@${ROSDISTRO_REF}" \
  "git+https://github.com/rep159-testing/rosdep@${ROSDEP_REF}"
python3 -c "import rosdistro, rosdep2; print(\"rosdistro\", rosdistro.__file__); print(\"rosdep\", rosdep2.__file__)"

step "rosdep from the index of the example"
export ROSDISTRO_INDEX_URL=file:///example/index-v4.yaml
rosdep init >/dev/null
rosdep update --rosdistro "$DISTRO"
for key in rclcpp geometry_msgs rosidl_default_generators generate_parameter_library; do
  printf "%-28s -> %s\n" "$key" "$(rosdep resolve "$key" --rosdistro "$DISTRO" 2>&1 | tail -1)"
done

step "The child distribution and its own repositories"
python3 /example/tools/check_extension.py "$ROSDISTRO_INDEX_URL" "$DISTRO" \
  --expect-from-parent rclcpp geometry_msgs --repos-file /tmp/own.repos
mkdir -p /ws/src && cd /ws
vcs import --input /tmp/own.repos src

step "rosdep install (from the Lyrical binaries)"
rosdep install --from-paths src --ignore-src --rosdistro "$DISTRO" -y -q \
  | grep -E "^#|executing|Setting up ros-" | grep -c "Setting up ros-lyrical-" \
  | sed "s/^/ros-lyrical-* debs installed: /" || true
rosdep check --from-paths src --ignore-src --rosdistro "$DISTRO"

step "colcon build and test on top of /opt/ros/lyrical"
set +u; . /opt/ros/lyrical/setup.sh; set -u
colcon build --executor sequential --event-handlers console_cohesion- summary+
colcon test --executor sequential --event-handlers console_direct- summary+ || true
colcon test-result --all || true
# grep -c exits 1 when it counts 0, which is the expected count of the second
dpkg -l "ros-*" | grep -c "^ii  ros-lyrical-" | sed "s/^/ros-lyrical-* installed: /" || true
dpkg -l "ros-*" | grep "^ii" | grep -vc "ros-lyrical-" | sed "s/^/other ros-* installed: /" || true
'
