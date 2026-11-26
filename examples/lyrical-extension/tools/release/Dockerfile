# Runner for tools/release_in_container.sh: the REP 159 tools from
# rep159.repos, colcon-ros-buildfarm and the Docker client. It drives the
# host's Docker daemon through its socket; it runs no daemon of its own.
#
# Build from the root of this repository (the context needs rep159.repos):
#   docker build -f examples/lyrical-extension/tools/release/Dockerfile \
#     -t rep159-guide-release-runner .
FROM ubuntu:resolute

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
 && apt-get install -qq -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu resolute main" \
    > /etc/apt/sources.list.d/ros2.list \
 && apt-get update -qq \
 && apt-get install -qq -y --no-install-recommends \
    docker.io \
    dpkg-dev \
    git \
    python3-catkin-pkg-modules \
    python3-colcon-common-extensions \
    python3-colcon-package-selection \
    python3-dateutil \
    python3-empy \
    python3-jenkinsapi \
    python3-packaging \
    python3-pytest \
    python3-rosdep \
    python3-rospkg-modules \
    python3-setuptools \
    python3-tomli-w \
    python3-vcstool \
    python3-vcstools \
    python3-yaml \
 && rm -rf /var/lib/apt/lists/*

# Only the six Python tools of rep159.repos the runner uses; they are pure
# Python, nothing compiles. One clone at a time over HTTP/1.1: parallel
# HTTP/2 clones from GitHub fail now and then.
COPY rep159.repos /tmp/rep159.repos
RUN mkdir -p /opt/rep159_ws/src \
 && python3 -c "import yaml; r = yaml.safe_load(open('/tmp/rep159.repos')); \
keep = ['rosdistro', 'rosdep', 'bloom', 'ros_buildfarm', 'colcon-ros-distro', 'colcon-ros-buildfarm']; \
r['repositories'] = {'tools/' + k: r['repositories']['tools/' + k] for k in keep}; \
yaml.safe_dump(r, open('/tmp/tools.repos', 'w'))" \
 && git config --system http.version HTTP/1.1 \
 && vcs import --workers 1 --retry 3 --input /tmp/tools.repos /opt/rep159_ws/src \
 && cd /opt/rep159_ws \
 && MAKEFLAGS=-j2 colcon build --executor sequential --merge-install \
    --event-handlers console_cohesion- \
 && rm -rf build log \
 && chmod -R a+rX /opt/rep159_ws

# rosdep init needs root; the runner itself runs as the host user.
RUN . /opt/rep159_ws/install/setup.sh && rosdep init

COPY examples/lyrical-extension/tools/release/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
