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
| [`rep159.repos`](rep159.repos) | Every REP 159 component as one colcon workspace, on its `rep159` branch or on the branch of an open pull request into `rep159`. |
| [`examples/lyrical-extension`](examples/lyrical-extension) | A third-party distribution, `my-extended-distro`, that extends the official ROS 2 Lyrical with `binary_import`: index, distribution file, checks, a container build, and the release steps. |
| [`docs/software_changed.md`](docs/software_changed.md) | The tools changed for REP 159, the branch of each one, and the features it adds. |
| [`docs/rosinstall_generator.md`](docs/rosinstall_generator.md) | What rosinstall_generator does with an extended distribution today, and what REP 159 support would add. |

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
