# Note: rosinstall_generator and REP 159

State on 2026-11-24. The REP lists, under Implementation:
"rosinstall_generator - traverse across distro boundaries appropriately".
That part does not exist yet.

ros_buildfarm does not use rosinstall_generator: its CI jobs walk the
dependencies with the rosdistro library. So nothing here blocks a release
or a farm job. rosinstall_generator is the tool for people who build from
source outside the farm.

## What it does today

With the REP 159 rosdistro installed, rosinstall_generator loads an
extended distribution, but only as one flat list: rosdistro hands it the
child merged with its parents. rosinstall_generator never reads `extends`,
`extension_method` or `origin_distro`. It cannot tell where the child ends
and the parent begins, or whether the parent is a `binary_import` or a
`source_rebuild` parent.

Upstream rosinstall_generator (master `96b6f03`) with the rosdistro of
`rep159.repos`, on the index of `examples/lyrical-extension`
(`acme` extends Lyrical with `binary_import`):

| Command | Result |
|---|---|
| `geometry_msgs --rosdistro acme --deps` | 95 Lyrical repositories, `release/lyrical/...` tags. The walk goes into the parent as if it were acme. |
| `dispatcher --rosdistro acme --deps` | dispatcher is ignored: it has only a source entry, and without `--upstream*` the tool only knows released packages. |
| `dispatcher --rosdistro acme --upstream-development --deps` | dispatcher alone. Right for `binary_import`, but by accident: the official Lyrical cache has no source manifests (0 source, 1846 release), so the dependencies on Lyrical (`rclcpp`, ...) drop out as unknown. |
| `rclcpp --rosdistro acme --upstream-development --deps` | Fails: "The following unreleased packages/stacks will be ignored: rclcpp". |

[KmoM88/rosinstall_generator `feature/rep-2015-tool-integration`](https://github.com/KmoM88/rosinstall_generator/tree/feature/rep-2015-tool-integration)
(4 commits) adds tests of this flat merge and evaluates the release tag
template for `--upstream`. It does not add any boundary logic.

## What REP 159 support would add

1. **Stop at a `binary_import` parent.** `--deps` of a child package
   lists the child's repositories only. The parent's packages are
   binaries (`ros-lyrical-*`) that rosdep installs. ros_buildfarm's CI
   walk already applies this rule (`rep159` branch, "REP 159: the CI
   dependency walk stops at binary_import parents"). Optionally, print
   the parent packages the workspace needs installed.
2. **Walk into a `source_rebuild` parent** on purpose, the child's own
   entries winning over the parent's. This is close to today's flat
   behavior. Each parent repository keeps its own release repository and
   tag template.
3. **Go through a binary parent on request** (for example
   `--deps-through-parents`), for a platform or architecture where the
   parent has no binaries, to get the whole stack from source.
4. **Different versions on each side of the boundary.** Development
   branches for the child's repositories, release tags for the parent's.
   Today `--upstream-development` applies to everything and fails on the
   parent, whose cache has no source manifests.
5. **Output split by distribution** (`acme.repos`, `lyrical.repos`), to
   build two chained workspaces, the way `/opt/ros/acme` chains
   `/opt/ros/lyrical`.

## Use cases

- **A developer of the child distribution**: a workspace with their
  package and the child packages it needs, on top of `/opt/ros/lyrical`.
  Until then, `examples/lyrical-extension/tools/check_extension.py
  --repos-file` writes all the child's own repositories, without any
  selection by dependency.
- **A `source_rebuild` extension**, for example a ROS distribution that
  extends Gazebo Jetty: "gz-sim and its dependencies" as a `.repos` file,
  the same set a ros_buildfarm CI job selects with `package_names` and
  `package_dependencies`. It replaces hand-maintained files such as
  `gz_vendor.repos`.
- **Building from source where the parent has no binaries**: item 3 gives
  the whole stack in one file.
- **CI outside ros_buildfarm** that starts from a repos file (industrial_ci
  upstream workspaces, action-ros-ci): generated from the distribution, it
  follows the releases instead of being edited by hand.
