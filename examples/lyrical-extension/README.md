# Example: a third-party distribution that extends ROS 2 Lyrical

This directory is a complete REP 159 index for one distribution, `acme`. It
extends the official ROS 2 Lyrical (the one in
[ros/rosdistro](https://github.com/ros/rosdistro)) with
`extension_method: binary_import`. That is the REP's use case 2
("Externally Managed Distro Extension"). A third party keeps its own
distribution and its own package repository. Its packages build against
the official `ros-lyrical-*` binaries and install as `ros-acme-*` in
`/opt/ros/acme`.

`acme` holds two real community packages that are released for Jazzy or
Kilted but not for Lyrical. All of their ROS dependencies are in Lyrical:

| Repository | Package | Uses from Lyrical |
|---|---|---|
| [qleonardolp/kinematic_pose_msgs](https://github.com/qleonardolp/kinematic_pose_msgs) | message package | `geometry_msgs`, the rosidl generators |
| [nasa-jpl/dispatcher](https://github.com/nasa-jpl/dispatcher) | C++ and Qt 5 application, with gtest | `rclcpp`, `std_msgs`, `sensor_msgs`, `std_srvs` |

| File | What it is |
|---|---|
| `index-v4.yaml` | The third party's index. It lists only `acme`. |
| `acme/distribution.yaml` | Distribution file version 3, `extends: lyrical`, with comments on the rules. |
| `acme-cache.yaml.gz` | The distribution cache, from `tools/regenerate-cache.sh`. |
| `tools/check_extension.py` | Loads the child with its parents merged and reports what it owns. |
| `tools/build_in_container.sh` | Builds and tests the child's packages against the Lyrical binaries in a clean `ubuntu:resolute`. |

## 1. Tools

The REP 159 versions of rosdistro, rosdep, bloom and ros_buildfarm are not
released yet. `rep159.repos`, at the root of this repository, pins a set
that works together; build it once with colcon:

```bash
mkdir -p rep159_ws/src && cd rep159_ws
vcs import --input <this repository>/rep159.repos src
colcon build --merge-install
source install/setup.bash
```

## 2. The distribution file

```yaml
extends:
- distro_name: lyrical
  index_url: https://raw.githubusercontent.com/ros/rosdistro/master/index-v4.yaml
  extension_method: binary_import
```

- `index_url` names the index that defines the parent. Lyrical's
  distribution file and its cache (`repo.ros2.org/rosdistro_cache`) are read
  from there, so the third party copies nothing from ros/rosdistro.
- `binary_import` means acme uses Lyrical's binaries unchanged. rosdep maps
  every Lyrical package to `ros-lyrical-*`, and the packages acme releases
  are named `ros-acme-*`.
- A `binary_import` child cannot redefine a Lyrical repository or package.
  rosdistro refuses to load it ("not allowed to override repository
  'rclcpp' from base distribution 'lyrical' under extension_method
  'binary_import'"). Rebuilding Lyrical packages under the child's name is
  `source_rebuild`.
- The one exception is the child's workspace package (`ros_workspace`, or
  the one named by `workspace_package`). Releasing it into acme gives
  `/opt/ros/acme/setup.sh`, which sources `/opt/ros/lyrical/setup.sh`. It
  must carry its own release stanza; a source entry alone is refused.

## 3. Check it and build the cache

```bash
tools/regenerate-cache.sh
python3 tools/check_extension.py file://$PWD/index-v4.yaml acme \
    --expect-from-parent rclcpp geometry_msgs
```

```
extends lyrical (binary_import) from https://raw.githubusercontent.com/ros/rosdistro/master/index-v4.yaml
754 repositories after the merge: 2 own, 752 from lyrical
  own: dispatcher source https://github.com/nasa-jpl/dispatcher.git@master
  own: kinematic_pose_msgs source https://github.com/qleonardolp/kinematic_pose_msgs.git@master
OK   rclcpp: origin lyrical, binary_import
OK   geometry_msgs: origin lyrical, binary_import
cache: 754 repositories, 1871 release package.xmls, own source manifests complete
```

The cache line exercises what rosdep and ros_buildfarm use: acme's cache,
merged with Lyrical's cache downloaded through `index_url`.

## 4. Develop against the Lyrical binaries

On an Ubuntu resolute machine with the ROS 2 apt repository and the tools
of section 1:

```bash
export ROSDISTRO_INDEX_URL=file://$PWD/index-v4.yaml   # or the published URL
rosdep update --rosdistro acme
rosdep resolve rclcpp --rosdistro acme       # ros-lyrical-rclcpp
python3 tools/check_extension.py $ROSDISTRO_INDEX_URL acme --repos-file acme.repos
mkdir -p ws/src && vcs import --input acme.repos ws/src && cd ws
rosdep install --from-paths src --ignore-src --rosdistro acme -y
. /opt/ros/lyrical/setup.sh
colcon build && colcon test
```

Pass `--rosdistro acme` to rosdep: `/opt/ros/lyrical/setup.sh` sets
`ROS_DISTRO=lyrical`.

`tools/build_in_container.sh` runs the same steps in a clean
`ubuntu:resolute` container, with rosdistro and rosdep pip-installed from
the pinned commits:

```
rclcpp                       -> ros-lyrical-rclcpp
geometry_msgs                -> ros-lyrical-geometry-msgs
rosidl_default_generators    -> ros-lyrical-rosidl-default-generators
...
ros-lyrical-* debs installed: 111
All system dependencies have been satisfied
...
Summary: 2 packages finished [47.4s]
Summary: 145 tests, 0 errors, 0 failures, 29 skipped
ros-lyrical-* installed: 111
other ros-* installed: 0
```

(Run of 2026-11-24, `ubuntu:resolute` with packages.ros.org.)

Porting is still the package's own job. Jazzy and Kilted packages often need
changes for Lyrical, and this setup exposes that as soon as you build.
Two candidates for this example failed for that reason:
`husarion/tf_namespace_bridge` (`jazzy`) calls `ament_target_dependencies`,
which Lyrical's ament_cmake no longer has, and
`ros-drivers/mocap_optitrack` (`foxy-devel`) includes
`geometry_msgs/msg/pose2_d.hpp`, which Lyrical's `geometry_msgs` no longer
ships.

## 5. Releasing debs

The steps, in order. Only the debian metadata was checked here, not a
release (see the table below).

1. **Publish the index** in a GitHub repository. bloom reads the index from
   `ROSDISTRO_INDEX_URL` and opens its pull requests against the repository
   and branch in that URL, so use the raw URL of a branch whose name has no
   `/`: `https://raw.githubusercontent.com/<org>/<repo>/<branch>/index-v4.yaml`.
2. **Release `ros_workspace` into acme first**, from the REP 159 fork
   (`rep159-testing/ros_workspace`, branch `rep159`). Upstream
   `ros2/ros_workspace` does not chain parent prefixes. Without it, acme's
   packages depend on `ros-lyrical-ros-workspace`, and nothing installs
   `/opt/ros/acme/setup.sh`.
3. **Release each repository** with the REP 159 bloom: an empty
   `<repo>-release` repository, then
   `ROSDISTRO_INDEX_URL=<raw URL> bloom-release --rosdistro acme --track acme <repo>`.
   bloom adds the release stanza and opens the pull request against the
   index; merge it and regenerate the cache.
4. **Build the debs**, with ros_buildfarm release jobs (a farm and a
   `ros_buildfarm_config` for acme) or by hand from the release
   repository's `debian/acme/<package>` branch.
5. **Host them in an apt repository.** Users add it next to
   packages.ros.org.

What bloom's `rosdebian` generator (the code `bloom-release` runs) produces
for this index:

| | acme without its own `ros_workspace` | acme releasing `ros_workspace` |
|---|---|---|
| package name | `ros-acme-kinematic-pose-msgs` | same |
| install prefix, parent prefixes in `debian/rules` | `/opt/ros/acme`; `/opt/ros/lyrical` | same |
| Depends | `ros-lyrical-geometry-msgs`, `ros-lyrical-rosidl-default-runtime`, `ros-lyrical-ros-workspace` | the same, with `ros-acme-ros-workspace` instead |
| `ros-acme-ros-workspace` | not built | Depends `ros-lyrical-ros-workspace`; its `setup.sh` sources `/opt/ros/lyrical` |

Use `bloom-release` (or `git-bloom-generate`) only. The standalone
`bloom-generate rosdebian` maps the dependencies the same way, but it sets
no parent prefix and does not add the workspace package. Its
`debian/rules` searches only `/opt/ros/acme`.

## Not covered yet (state on 2026-11-24)

- **ros_buildfarm jobs.** The pinned ros_buildfarm installs the stock apt
  `python3-rosdistro-modules` and `python3-rosdep-modules` in its job
  containers. Those cannot read a version 3 distribution file, so CI and
  release jobs for acme fail until REP 159 rosdistro and rosdep are
  released to the ROS apt repositories, or the containers are patched to
  pip-install the forks.
- **rosinstall_generator** reads an extended distribution as one flat
  list: `--deps` walks into Lyrical's repositories, and acme's unreleased
  packages need `--upstream-development`. Use
  `tools/check_extension.py --repos-file` for the child's own
  repositories. See [the rosinstall_generator note](../../docs/rosinstall_generator.md).
- **Lyrical has no `distribution_eol_date`** in the official index, so the
  check that a child does not outlive its parent has nothing to compare
  against.
- **Parents of parents across indexes.** ros_buildfarm follows a parent's
  own parents only when they are in the child's index. Lyrical has none,
  so acme is not affected.
- **The pins move.** The REP 159 pull requests are being merged into one
  `rep159` branch per repository; refresh `rep159.repos` from the pull
  requests and branches named in its comments.
