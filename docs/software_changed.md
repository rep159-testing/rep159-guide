# Software changed for REP 159

The REP 159 versions of the tools live in the
[rep159-testing](https://github.com/rep159-testing) organization, and
[`rep159.repos`](../rep159.repos) lists them as one colcon workspace. Each
tool collects its REP 159 work on a `rep159` branch. For bloom and
ros_buildfarm, part of that work is still on a branch with an open pull
request into `rep159` (2026-11-27), and `rep159.repos` uses that branch
until it is merged.

| Repository | Branch | Changes |
|---|---|---|
| [rosdistro](https://github.com/rep159-testing/rosdistro) | [`rep159`](https://github.com/rep159-testing/rosdistro/tree/rep159) | [Distribution format 3, index format 4](#rosdistro) |
| [rosdep](https://github.com/rep159-testing/rosdep) | [`rep159`](https://github.com/rep159-testing/rosdep/tree/rep159) | [Keys of extended distributions](#rosdep) |
| [bloom](https://github.com/rep159-testing/bloom) | [`feat/rep159-workspace-package`](https://github.com/rep159-testing/bloom/tree/feat/rep159-workspace-package) | [Debian packages built against the parents](#bloom) |
| [ros_buildfarm](https://github.com/rep159-testing/ros_buildfarm) | [`feat/rep159-core`](https://github.com/rep159-testing/ros_buildfarm/tree/feat/rep159-core) | [CI and release jobs](#ros_buildfarm) |
| [colcon-ros-distro](https://github.com/rep159-testing/colcon-ros-distro) | [`rep159`](https://github.com/rep159-testing/colcon-ros-distro/tree/rep159) | [Own packages of an extended distribution](#colcon-ros-distro) |
| [rosdistro-reviewer](https://github.com/rep159-testing/rosdistro-reviewer) | [`rep159`](https://github.com/rep159-testing/rosdistro-reviewer/tree/rep159) | [End-of-life dates](#rosdistro-reviewer) |
| [reprepro-updater](https://github.com/rep159-testing/reprepro-updater) | [`rep159`](https://github.com/rep159-testing/reprepro-updater/tree/rep159) | [Package prefix in the sync jobs](#reprepro-updater) |
| [ros_workspace](https://github.com/rep159-testing/ros_workspace) | [`rep159`](https://github.com/rep159-testing/ros_workspace/tree/rep159) | [Setup files that chain the parents](#ros_workspace) |
| [ros_workspace_shell](https://github.com/rep159-testing/ros_workspace_shell) | [`rep159`](https://github.com/rep159-testing/ros_workspace_shell/tree/rep159) | [Setup files without ament](#ros_workspace_shell) |

## rosdistro

Distribution file format version 3:

- **`extends`**: the parents of a distribution, each with `distro_name`,
  `extension_method` (`binary_import` or `source_rebuild`) and an
  optional `index_url`, the index that holds the parent (by default, the
  child's own index). Loading a distribution loads its parents, and their
  parents, from those indexes. A parent that cannot be loaded is an error.
- **Merge rules.** The child's repositories take precedence over its
  parents'. Between parents, the first one in `extends` wins, and the
  collision is logged as a warning. Every repository and its release
  entry record where they come from: `origin_distro` and
  `extension_method`.
- **`binary_import` keeps the parent's binaries.** A child cannot
  redefine a repository or a package of a `binary_import` parent;
  rosdistro refuses to load it. Redefining is only allowed under
  `source_rebuild`.
- **`workspace_package`**: the package that installs the setup files of
  the distribution's prefix, `ros_workspace` by default
  (`ros_workspace_shell` for a distribution without ament). It is the one
  exception to the rule above: a `binary_import` child may release its
  own, keeping the parent's source and doc entries, and it must give its
  own release entry. Since `ros_workspace` depends on
  `ros_workspace_shell` for the setup files of its prefix, a child that
  releases its own `ros_workspace` may release its own
  `ros_workspace_shell` too
  ([rosdistro#4](https://github.com/rep159-testing/rosdistro/pull/4)).
  Releasing `ros_workspace_shell` alone is still refused. Releasing
  `ros_workspace` while taking `ros_workspace_shell` from the parent
  logs a warning: the shell's setup files would go to the parent's
  prefix, not the child's.
- **`binary_rule`**: the binary package names of a distribution, as a
  regular expression `search` and `replace` with the placeholders
  `{distro}`, `{package}` and `{origin_distro}`. It can be set on the
  distribution, on an `extends` entry or on a repository's release entry;
  the repository's rule wins. `get_binary_package_name()` applies it,
  `get_package_name_from_binary()` maps a binary name back to its
  package, and package names with hyphens (`gz-math`) are found too.
- **`install_rule`**: the install prefix, as a string template or a
  `search` and `replace` rule with the same placeholders, at the same
  three levels. `get_install_prefix()` returns it, `/opt/ros/<distro>` by
  default.
- **`dependencies`**: the rosdep sources list URLs and minimum target
  platforms of the distribution. A release platform of the child that a
  parent does not support is logged as a warning.
- **Caches.** Loading a child's cache merges its parents' caches, read
  through `index_url`. `binary_rule` is kept in the cache.

Index format version 4:

- **`distribution_eol_date`** on each distribution, a `YYYY-MM-DD` date,
  parsed and validated.

## rosdep

- A key that is a package of the distribution resolves through rosdistro's
  `get_binary_package_name()`:
  - a package of a `binary_import` parent resolves to the parent's binary
    (`rclcpp` in a child of Lyrical: `ros-lyrical-rclcpp`);
  - the child's own packages, and those of a `source_rebuild` parent,
    resolve to the child's names (`ros-<child>-*`);
  - a `binary_rule` replaces either name where it applies.
- `rosdep update --rosdistro <child>` loads the child with its parents
  merged, so the parents' packages are keys of the child.

## bloom

- **Parents.** bloom finds a distribution's `binary_import` parents in
  the index, through `index_url`, transitively and nearest first. A parent
  that cannot be read, or a cycle, stops the release with the names of the
  distributions involved. Only ROS 2 distributions are walked.
- **`debian/rules`** (ament_cmake and cmake templates). Every build step
  sources each parent's `setup.sh` before the distribution's own, and
  unsets `AMENT_CURRENT_PREFIX` after each one, so a parent cannot leak it
  into the next parent's plain-CMake setup files. The parents' prefixes
  follow the install prefix in `PKG_CONFIG_PATH`, `CMAKE_PREFIX_PATH` and
  `AMENT_PREFIX_PATH`. Without parents the rules are the same as before.
- **Workspace package.** Every package of the distribution depends on the
  distribution's `workspace_package`. `ament_cmake_core` and
  `ament_package` are left out only when that package is `ros_workspace`.
  The workspace package itself is built with
  `-DROS_WORKSPACE_PARENT_PREFIX_PATH` set to the parents' prefixes, and
  depends on each parent's own workspace package.
- **Names and prefixes.** Debian package names come from
  `get_binary_package_name()` (`binary_rule`). The install prefix and the
  parents' prefixes come from `get_install_prefix()` (`install_rule`).
- **Loading.** bloom resolves `extends` when it loads the distribution,
  so the inherited rules apply without a prebuilt cache of the child, and
  a distribution that fails to load is reported instead of ignored.
- `git tag -f` gets a message, so tagging works with `tag.gpgSign=true`.

## ros_buildfarm

CI jobs:

- **Source-only packages.** With `package_names` and
  `package_dependencies`, the dependency walk includes packages that only
  have a source entry, in the distribution or in a `source_rebuild`
  parent, and checks them out from that entry. Released packages are
  still checked out from their release repository and tag.
- **The walk stops at `binary_import` parents.** Their packages come as
  binaries, so they are neither checked out nor walked through.
  `source_rebuild` parents are walked.
- **Underlays.** The `binary_import` parents, and their parents, are
  sourced before the build: root first, a parent reached twice (a
  diamond) only once. Their prefixes come from `install_rule`,
  `/opt/ros/<parent>` by default, followed by the distribution's own.
- **Environment.** With a parent's `setup.sh`, `CMAKE_PREFIX_PATH` is
  exported too (for plain-CMake packages under a `ros_workspace_shell`
  prefix). Without one, the job sets `CMAKE_PREFIX_PATH`,
  `COLCON_PREFIX_PATH`, `LD_LIBRARY_PATH` and `PATH` itself.
  `AMENT_CURRENT_PREFIX` is unset after each parent.
- A parent distribution that cannot be loaded when the job is
  generated is an error, instead of a job without that underlay.

Release jobs:

- **Names.** `get_os_package_name()` uses the distribution's
  `binary_rule`: in the generated jobs, in the binarydeb task and in the
  sync criteria. The release scripts receive the resulting name
  (`--debian-package-name`).
- **Own packages only.** Jobs are generated for the child's release
  packages; the parents' packages, merged into the cache, are skipped.
- **Workspace package.** The release job graph uses the distribution's
  `workspace_package` (`ros_workspace` or, for example,
  `ros_workspace_shell`) for the build dependency triggers.
- **Sync jobs** pass the distribution's package prefix to
  reprepro-updater (`--package-prefix`).

Job containers install rosdistro and rosdep from the ROS apt repositories,
as upstream ros_buildfarm does. Jobs for an extended distribution need
the REP 159 versions of both released there.

## colcon-ros-distro

- **Own packages only.** colcon-ros-distro discovers a distribution's
  released packages for colcon-ros-buildfarm. It now skips the
  repositories that REP 159 rosdistro marks as coming from a
  `binary_import` parent (`origin_distro` is another distribution), and
  logs how many it skipped. The repositories of a `source_rebuild` parent
  are still discovered, since the child rebuilds them. With a rosdistro
  that has no REP 159 support, nothing changes. Used by the example's
  [local release](../examples/lyrical-extension/README.md#6-release-the-debs-locally).

## rosdistro-reviewer

- Checks that each `distribution_eol_date` in `index-v4.yaml` is a
  `YYYY-MM-DD` date, and recommends disapproval otherwise.
- For a distribution that `extends` another, recommends disapproval when
  the parent reaches its end of life before the child.
- Reads `extends` entries by `distro_name`, as rosdistro does.

## reprepro-updater

- `sync_ros_packages.py --package-prefix <prefix>` (for example
  `vendor-extendable-`): the sync filter and the cleanup select the
  packages by that prefix instead of `ros-<rosdistro>-`. For distributions
  whose binary names come from a `binary_rule`.

## ros_workspace

- With `ROS_WORKSPACE_PARENT_PREFIX_PATH` set (bloom sets it for the
  workspace package; `PARENT_PREFIX_PATH` is accepted too), the parents
  are recorded as the package's `parent_prefix_path` resource. The setup
  files of the prefix (`/opt/ros/<child>/setup.sh` and the others) then
  source each parent's `local_setup` first.
- `ament_package` is also looked for in the parents' prefixes.
- With no parents, it installs the same files as before. Version 1.0.4.

## ros_workspace_shell

- A new package: the setup files in the root of a prefix (`setup.*`,
  `local_setup.*`, `_local_setup_util.py`) and the prefix's environment,
  built with plain CMake. Neither building nor using it needs ament. It is
  the workspace package of a distribution without ament packages
  (`workspace_package: ros_workspace_shell`).
- It chains parent distributions the same way as `ros_workspace`, with
  `ROS_WORKSPACE_PARENT_PREFIX_PATH`.

## Also in `rep159.repos`

- `ament_package` (0.18.3) and `ament_cmake_core` (2.8.8), unchanged, to
  build `ros_workspace`. Branch `main`.
- `colcon-ros-buildfarm`, unchanged, from
  [colcon/colcon-ros-buildfarm](https://github.com/colcon/colcon-ros-buildfarm)
  at a commit that is not on PyPI yet, for the example's local release.
- The indexes and buildfarm configurations of the rep159-testing
  organization: `rep159-rosdistro` and `ros_buildfarm_config`, branches
  `feat/extendable-gazebo` and `rep159-shell`.
