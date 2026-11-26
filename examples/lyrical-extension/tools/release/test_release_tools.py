"""Unit tests for release_tools.py; run them in the runner image:

  docker run --rm -v "$PWD/examples/lyrical-extension:/example:ro" \
    rep159-guide-release-runner python3 -m pytest -q -p no:cacheprovider \
    /example/tools/release
"""

import os

import pytest
import yaml

import release_tools as rt

DISTRO = 'my-extended-distro'
GIT_URL = 'git://127.0.0.1:19418/dispatcher-release.git'
HERE = os.path.dirname(os.path.abspath(__file__))


def _pool(*names):
    files = []
    for name in names:
        deb = rt.debian_name(DISTRO, name)
        files += [f'{deb}_1.0.0-1resolute.dsc',
                  f'{deb}_1.0.0-1resolute_amd64.deb']
    return files


def test_debian_name():
    assert rt.debian_name(DISTRO, 'kinematic_pose_msgs') == \
        'ros-my-extended-distro-kinematic-pose-msgs'


def test_release_stanza_tag_is_literal():
    dist = {'repositories': {'dispatcher': {}}}
    rt.add_release_stanza(
        dist, 'dispatcher', distro=DISTRO, url=GIT_URL, version='0.4.5-1')
    release = dist['repositories']['dispatcher']['release']
    assert release == {
        'tags': {'release': 'release/my-extended-distro/{package}/{version}'},
        'url': GIT_URL,
        'version': '0.4.5-1',
    }
    assert '{distro}' not in release['tags']['release']


def test_release_stanza_lists_packages_only_when_given():
    dist = {'repositories': {'repo': {}}}
    rt.add_release_stanza(dist, 'repo', distro=DISTRO, url=GIT_URL,
                          version='1.0.0-1', packages=['a', 'b'])
    assert dist['repositories']['repo']['release']['packages'] == ['a', 'b']


def test_release_stanza_loads_with_rosdistro():
    from rosdistro.distribution_file import DistributionFile
    dist = {'type': 'distribution', 'version': 2,
            'repositories': {'dispatcher': {}}}
    rt.add_release_stanza(
        dist, 'dispatcher', distro=DISTRO, url=GIT_URL, version='0.4.5-1')
    repo = DistributionFile('d', dist).repositories['dispatcher']
    assert repo.release_repository.get_release_tag('dispatcher') == \
        'release/my-extended-distro/dispatcher/0.4.5-1'


def test_add_repository_refuses_duplicate():
    dist = {'repositories': {'ros_workspace': {}}}
    with pytest.raises(ValueError):
        rt.add_repository(dist, 'ros_workspace', {'type': 'git'})


def test_make_tracks_defaults():
    tracks = rt.make_tracks(
        distro=DISTRO, vcs_uri='https://example.invalid/x.git',
        devel_branch='master', release_tag='v:{version}',
        push_url='file:///work/git/x-release.git', actions=['a'])
    track = tracks['tracks'][DISTRO]
    assert track['release_inc'] == 0
    assert track['version'] == ':{auto}'
    assert track['release_tag'] == 'v:{version}'
    assert 'last_version' not in track
    assert track['release_repo_url'].startswith('file://')
    assert track['ros_distro'] == DISTRO
    assert track['actions'] == ['a']


def test_releases_yaml_values():
    with open(os.path.join(HERE, 'releases.yaml')) as f:
        releases = yaml.safe_load(f)
    repos = releases['repositories']
    assert releases['distro'] == DISTRO
    assert releases['parent'] == 'lyrical'
    assert releases['workspace_package'] == 'ros_workspace'
    assert list(repos) == ['ros_workspace', 'kinematic_pose_msgs',
                           'dispatcher']
    assert repos['dispatcher']['release_tag'] == 'v:{version}'
    assert repos['kinematic_pose_msgs']['release_tag'] == ':{version}'
    assert repos['ros_workspace']['version'] == '1.0.4-1'
    assert repos['ros_workspace']['source']['version'] == 'rep159'


def test_release_version_picks_single_tag():
    tags = ['upstream/0.4.5', 'release/my-extended-distro/dispatcher/0.4.5-1']
    assert rt.release_version(tags, distro=DISTRO, package='dispatcher') == \
        '0.4.5-1'


@pytest.mark.parametrize('tags', [
    [],
    ['release/my-extended-distro/dispatcher/0.4.5-1',
     'release/my-extended-distro/dispatcher/0.4.5-2'],
])
def test_release_version_rejects_none_or_many(tags):
    with pytest.raises(ValueError):
        rt.release_version(tags, distro=DISTRO, package='dispatcher')


def test_buildfarm_config_loads_with_ros_buildfarm():
    from ros_buildfarm.config.index import Index
    from ros_buildfarm.config.release_build_file import ReleaseBuildFile
    index, release_build = rt.buildfarm_config(
        distro=DISTRO,
        rosdistro_index_url='http://127.0.0.1:18159/index/index-v4.yaml',
        ros_key='-----BEGIN PGP PUBLIC KEY BLOCK-----', makeflags='-j2')
    # ros_buildfarm's get_index passes the index URL's dirname, no slash.
    loaded = Index(index, 'http://127.0.0.1:18159/config')
    assert loaded.rosdistro_index_url == \
        'http://127.0.0.1:18159/index/index-v4.yaml'
    assert loaded.distributions[DISTRO]['release_builds']['default'] == \
        'http://127.0.0.1:18159/config/my-extended-distro/release-build.yaml'
    build = ReleaseBuildFile('default', release_build)
    assert build.build_environment_variables == {'MAKEFLAGS': '-j2'}
    assert build.targets == {'ubuntu': {'resolute': {'amd64': {}}}}
    assert build.repository_urls == ['http://packages.ros.org/ros2/ubuntu']


def test_buildfarm_config_cli_refuses_binary_key(tmp_path, capsys):
    # ros/rosdistro's ros.key is a binary key; the Dockerfiles ros_buildfarm
    # writes need the ASCII-armored ros.asc.
    key = tmp_path / 'ros.key'
    key.write_bytes(b'\x99\x02\r\x04\\\xef')
    assert rt.main([
        'buildfarm-config', str(tmp_path / 'config'),
        '--index-url', 'http://127.0.0.1:18159/index/index-v4.yaml',
        '--ros-key', str(key), '--makeflags=-j2']) == 1
    assert 'not an ASCII-armored public key' in capsys.readouterr().err
    assert not (tmp_path / 'config').exists()


PACKAGES = ['ros_workspace', 'kinematic_pose_msgs', 'dispatcher']
SKIP = ("Skipping 676 repositories that 'my-extended-distro' takes from "
        "'lyrical' as binaries")
VENDORED = 'commit 1234\n    Vendor the REP 159 rosdistro df99d83 (local)\n'


def test_check_discovered_exact():
    assert rt.check_discovered(sorted(PACKAGES), packages=PACKAGES) == []


def test_check_discovered_refuses_parent_packages():
    errors = rt.check_discovered(
        PACKAGES + ['rclcpp', 'geometry_msgs'], packages=PACKAGES)
    assert errors == [
        'colcon-ros-distro would build 2 packages that are not the '
        "child's own: geometry_msgs, rclcpp"]


def test_check_discovered_reports_missing():
    assert rt.check_discovered(['dispatcher'], packages=PACKAGES) == [
        'colcon-ros-distro does not discover: kinematic_pose_msgs, '
        'ros_workspace']


def test_check_logs_good():
    texts = [f'INFO:colcon.colcon_ros_distro:{SKIP}\n'] + [VENDORED] * 3
    assert rt.check_logs(texts, distro=DISTRO, parent='lyrical',
                         packages=PACKAGES) == ([SKIP], 3, [])


def test_check_logs_cli_prints_why(tmp_path, capsys):
    # No skip line, and no job log with the vendoring commit: the jobs ran
    # with the stock rosdistro. The command must say so, not just fail.
    (tmp_path / 'latest').mkdir()
    (tmp_path / 'latest' / 'logger_all.log').write_text(
        'Summary: 3 packages finished\n')
    assert rt.main(['check-logs', str(tmp_path)]) == 1
    err = capsys.readouterr().err
    assert "did not report skipping the 'lyrical' repositories" in err
    assert ('only 0 job logs show the vendored rosdistro commit, '
            'expected at least 3') in err


def test_check_pool_exact():
    pkgs = ['ros_workspace', 'kinematic_pose_msgs', 'dispatcher']
    files = _pool(*pkgs)
    assert rt.check_pool(files, distro=DISTRO, packages=pkgs) == []

    errors = rt.check_pool(files + ['ros-lyrical-rclcpp_1.0-1_amd64.deb'],
                           distro=DISTRO, packages=pkgs)
    assert len(errors) == 1 and 'ros-lyrical-rclcpp' in errors[0]

    no_dsc = [f for f in files
              if not (f.startswith('ros-my-extended-distro-dispatcher_')
                      and f.endswith('.dsc'))]
    errors = rt.check_pool(no_dsc, distro=DISTRO, packages=pkgs)
    assert len(errors) == 1 and 'dispatcher' in errors[0]


CONTROL = '''Package: ros-my-extended-distro-kinematic-pose-msgs
Version: 1.0.0-1resolute
Depends: {depends}
'''
GOOD_PATHS = [
    './', './opt/', './opt/ros/', './opt/ros/my-extended-distro/',
    './usr/', './usr/share/', './usr/share/doc/',
    './usr/share/doc/ros-my-extended-distro-kinematic-pose-msgs/'
    'changelog.Debian.gz',
    './opt/ros/my-extended-distro/share/kinematic_pose_msgs/package.xml',
    './opt/ros/my-extended-distro/lib/libkinematic_pose_msgs.so',
]


def _check(depends, paths=GOOD_PATHS, package='kinematic_pose_msgs'):
    return rt.check_deb(control=CONTROL.format(depends=depends), paths=paths,
                        distro=DISTRO, parent='lyrical', package=package,
                        workspace_package='ros_workspace')


def test_check_deb_good():
    assert _check('ros-lyrical-geometry-msgs, '
                  'ros-my-extended-distro-ros-workspace') == []


def test_check_deb_needs_parent_dependency():
    assert len(_check('ros-my-extended-distro-ros-workspace')) == 1


def test_check_deb_needs_workspace_dependency():
    assert len(_check('ros-lyrical-geometry-msgs')) == 1


def test_check_deb_files_under_prefix():
    errors = _check('ros-lyrical-geometry-msgs, '
                    'ros-my-extended-distro-ros-workspace',
                    paths=GOOD_PATHS + ['./usr/lib/x'])
    assert len(errors) == 1 and './usr/lib/x' in errors[0]


def test_check_deb_workspace_package_has_no_dependency_rule():
    paths = ['./opt/ros/my-extended-distro/setup.sh']
    assert _check('', paths=paths, package='ros_workspace') == []
