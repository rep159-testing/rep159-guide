# Software changed for REP 159

The REP 159 versions of the tools live in the
[rep159-testing](https://github.com/rep159-testing) organization.
[`rep159.repos`](../rep159.repos) lists them as one colcon workspace.

Each tool has a `rep159` branch, and `rep159.repos` follows it. The four
main tools get their latest REP 159 work through a pull request into that
branch. Those pull requests are open (2026-11-25): until they are merged,
`rep159` has only the part of the table before the pull request number.

| Repository | Pull request into `rep159` | REP 159 support |
|---|---|---|
| [rosdistro](https://github.com/rep159-testing/rosdistro) | [#2](https://github.com/rep159-testing/rosdistro/pull/2) | `rep159`: format v3 `extends`, `origin_distro` and `extension_method` on each repository, precedence between several parents, parent caches loaded through `extends[].index_url`, overrides refused under `binary_import`. #2: `binary_rule` (binary package renaming), `install_rule` (install prefixes), `workspace_package`, the child's own `ros_workspace` release, `distribution_eol_date` in index v4. |
| [rosdep](https://github.com/rep159-testing/rosdep) | [#1](https://github.com/rep159-testing/rosdep/pull/1) | `rep159`: a `binary_import` child's keys resolve to the parent's binary packages, a `source_rebuild` child's to its own; naming delegated to rosdistro. #1: removes the test-bed index overrides, adds `binary_rule` tests. |
| [bloom](https://github.com/rep159-testing/bloom) | [#1](https://github.com/rep159-testing/bloom/pull/1) | `rep159`: finds the `binary_import` parents, puts their prefixes in `debian/rules`. #1: `binary_rule` names, `install_rule` prefixes, the distribution's workspace package as a dependency, `extends` resolved when bloom loads the distribution. |
| [ros_buildfarm](https://github.com/rep159-testing/ros_buildfarm) | [#1](https://github.com/rep159-testing/ros_buildfarm/pull/1) | `rep159`: CI jobs select source-only packages, source `binary_import` parents as underlays and stop the dependency walk at them. #1: `binary_rule` and `install_rule` in the release jobs, ancestor underlays resolved recursively, `--package-prefix` for the sync jobs, the workspace package in the release job graph. It also removes the `rep159` branch's test-only installs of the forks in the job containers. |
| [rosdistro-reviewer](https://github.com/rep159-testing/rosdistro-reviewer) | none | `distribution_eol_date` format, and a child must not outlive its parent. |
| [reprepro-updater](https://github.com/rep159-testing/reprepro-updater) | none | `--package-prefix` for the sync filters, for distributions whose packages are not named `ros-<distro>-*`. |
| [ros_workspace](https://github.com/rep159-testing/ros_workspace) | none | A child's `/opt/ros/<child>/setup.sh` sources its `binary_import` parents first. |
| [ros_workspace_shell](https://github.com/rep159-testing/ros_workspace_shell) | none | The same prefix-level setup files, built without ament. |

`rep159.repos` also lists `ament_package` and `ament_cmake_core` (needed
to build `ros_workspace`), and the indexes and buildfarm configurations of
the rep159-testing test harness. They have no `rep159` branch; their
entries name the branch they follow.
