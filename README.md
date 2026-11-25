# REP 159: how to use the implementation

[REP 159](https://github.com/openrobotics/reps/pull/32) (rosdistro
extensions, first drafted as REP 2015) lets one ROS distribution extend
another. A distribution file of format version 3 names its parents under
`extends`, each with an `extension_method`:

- `binary_import`: the child uses the parent's binaries as they are
  (`ros-lyrical-*` in `/opt/ros/lyrical`) and releases only its own
  packages, under its own name and prefix.
- `source_rebuild`: the child rebuilds the parent's packages from source
  under its own name.

The tools that read rosdistro need changes for this: rosdistro, rosdep,
bloom, ros_buildfarm and a few more. Their REP 159 versions live in the
[rep159-testing](https://github.com/rep159-testing) organization. This
repository says which versions work together and how to use them.

| Path | What it is |
|---|---|
| [`rep159.repos`](rep159.repos) | Every REP 159 component, pinned, as one colcon workspace. |
| [`examples/lyrical-extension`](examples/lyrical-extension) | A third-party distribution, `acme`, that extends the official ROS 2 Lyrical with `binary_import`: index, distribution file, checks, a container build, and the release steps. |
| [`docs/rosinstall_generator.md`](docs/rosinstall_generator.md) | What rosinstall_generator does with an extended distribution today, and what REP 159 support would add. |

## Components

Each tool has a `rep159` branch. The four main tools get their latest REP
159 work through a pull request into that branch; `rep159.repos` pins the
head of each pull request.

| Repository | Ref in `rep159.repos` | REP 159 support |
|---|---|---|
| [rosdistro](https://github.com/rep159-testing/rosdistro) | [#2](https://github.com/rep159-testing/rosdistro/pull/2) | `rep159`: format v3 `extends`, `origin_distro` and `extension_method` on each repository, precedence between several parents, parent caches loaded through `extends[].index_url`, overrides refused under `binary_import`. #2: `binary_rule` (binary package renaming), `install_rule` (install prefixes), `workspace_package`, the child's own `ros_workspace` release, `distribution_eol_date` in index v4. |
| [rosdep](https://github.com/rep159-testing/rosdep) | [#1](https://github.com/rep159-testing/rosdep/pull/1) | `rep159`: a `binary_import` child's keys resolve to the parent's binary packages, a `source_rebuild` child's to its own; naming delegated to rosdistro. #1: removes the test-bed index overrides, adds `binary_rule` tests. |
| [bloom](https://github.com/rep159-testing/bloom) | [#1](https://github.com/rep159-testing/bloom/pull/1) | `rep159`: finds the `binary_import` parents, puts their prefixes in `debian/rules`. #1: `binary_rule` names, `install_rule` prefixes, the distribution's workspace package as a dependency, `extends` resolved when bloom loads the distribution. |
| [ros_buildfarm](https://github.com/rep159-testing/ros_buildfarm) | [#1](https://github.com/rep159-testing/ros_buildfarm/pull/1) | `rep159`: CI jobs select source-only packages, source `binary_import` parents as underlays and stop the dependency walk at them. #1: `binary_rule` and `install_rule` in the release jobs, ancestor underlays resolved recursively, `--package-prefix` for the sync jobs, the workspace package in the release job graph. It also removes the `rep159` branch's test-only installs of the forks in the job containers. |
| [rosdistro-reviewer](https://github.com/rep159-testing/rosdistro-reviewer) | `rep159` | `distribution_eol_date` format, and a child must not outlive its parent. |
| [reprepro-updater](https://github.com/rep159-testing/reprepro-updater) | `rep159` | `--package-prefix` for the sync filters, for distributions whose packages are not named `ros-<distro>-*`. |
| [ros_workspace](https://github.com/rep159-testing/ros_workspace) | `rep159` | A child's `/opt/ros/<child>/setup.sh` sources its `binary_import` parents first. |
| [ros_workspace_shell](https://github.com/rep159-testing/ros_workspace_shell) | `rep159` | The same prefix-level setup files, built without ament. |

`rep159.repos` also pins `ament_package` and `ament_cmake_core` (needed to
build `ros_workspace`), and the indexes and buildfarm configurations of
the rep159-testing test harness.

## Quick start

```bash
git clone https://github.com/rep159-testing/rep159-guide.git
mkdir -p rep159_ws/src && cd rep159_ws
vcs import --input ../rep159-guide/rep159.repos src
colcon build --merge-install
source install/setup.bash
```

Then follow [`examples/lyrical-extension`](examples/lyrical-extension) to
define a distribution on top of Lyrical, check it, build its packages
against the Lyrical binaries and release them.

## State on 2026-11-24

Checked with the pins in `rep159.repos`:

- The workspace builds with colcon. Unit tests: rosdistro 107 pass;
  bloom 54 pass with empy 4 (its REP 159 `debian/rules` template tests
  fail in the full suite with Ubuntu's empy 3); rosdistro-reviewer 198
  pass (its spell check needs a module that was not installed);
  ros_buildfarm 34 pass, and its flake8 and pep8 checks report style
  findings; rosdep 142 pass, and its 3 failures fail the same way with
  upstream rosdep on the same host.
- The `acme` example loads with Lyrical merged in through `index_url`.
  rosdep resolves Lyrical keys to `ros-lyrical-*`. Its two packages build
  and pass their tests against the Lyrical debs in a clean
  `ubuntu:resolute` container.
- bloom generates the expected Debian metadata for `acme` (names,
  prefixes, dependencies).

Not working yet:

- **ros_buildfarm jobs for a third party.** The job containers install
  the stock `python3-rosdistro-modules` and `python3-rosdep-modules`,
  which cannot read format v3, until the REP 159 versions are released.
- **rosinstall_generator** treats an extended distribution as one flat
  list; see [the note](docs/rosinstall_generator.md).
- Details in the example's
  [Not covered yet](examples/lyrical-extension/README.md#not-covered-yet-state-on-2026-11-24).
