#!/usr/bin/env bash
# Install the built packages in a clean ubuntu:resolute next to the Lyrical
# binaries from packages.ros.org, and check that the child's setup file
# chains to Lyrical's. Run by run_release.sh.
#
# Usage: smoke_install.sh REPO_BASE   (colcon-ros-buildfarm's local repository)
set -euo pipefail
REPO=$1
fail() { echo "smoke_install: $*" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -qq -y --no-install-recommends ca-certificates curl >/dev/null
# ros.key is already a binary keyring, as the ROS 2 install guide uses it.
curl -fsSL --retry 5 --retry-all-errors --max-time 300 \
  -o /usr/share/keyrings/ros-archive-keyring.gpg \
  https://raw.githubusercontent.com/ros/rosdistro/master/ros.key
echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu resolute main" \
  >/etc/apt/sources.list.d/ros2.list
echo "deb [trusted=yes] file:$REPO/ubuntu resolute main" >/etc/apt/sources.list.d/local.list
apt-get update -qq
apt-get install -qq -y --no-install-recommends \
  ros-my-extended-distro-dispatcher ros-my-extended-distro-kinematic-pose-msgs \
  ros-lyrical-ros2pkg ros-lyrical-ros2interface >/dev/null
dpkg -l 'ros-*' | grep -c '^ii  ros-lyrical-' | sed 's/^/ros-lyrical-* installed: /'
dpkg -l 'ros-*' | grep '^ii  ros-my-extended-distro-' | awk '{print $2, $3}'

set +u
. /opt/ros/my-extended-distro/setup.sh
set -u
prefix=$(ros2 pkg prefix kinematic_pose_msgs)
[ "$prefix" = /opt/ros/my-extended-distro ] || fail "kinematic_pose_msgs is in $prefix"
prefix=$(ros2 pkg prefix rclcpp)
[ "$prefix" = /opt/ros/lyrical ] || fail "rclcpp is in $prefix"
interfaces=$(ros2 interface package kinematic_pose_msgs)
[ -n "$interfaces" ] || fail "kinematic_pose_msgs has no interfaces"
echo "kinematic_pose_msgs interfaces: $interfaces"
echo SMOKE-OK
