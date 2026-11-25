#!/usr/bin/env python3
"""Helpers for release_in_container.sh: index, bloom tracks, config, checks.

Runs in the runner image (tools/release/Dockerfile). Every subcommand reads
the distribution, its parent and its workspace package from releases.yaml
(--releases, default: the file next to this script) and exits 1 with the
errors when a check fails.
"""

import argparse
import contextlib
import os
import re
import shutil
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def debian_name(distro, package):
    return f"ros-{distro}-{package.replace('_', '-')}"


def release_tag_template(distro):
    # rosdistro only expands {package}, {version} and {upstream_version}:
    # the distribution name has to be literal.
    return f'release/{distro}/{{package}}/{{version}}'


def add_repository(dist, name, source):
    repos = dist.setdefault('repositories', {})
    if name in repos:
        raise ValueError(f"repository '{name}' already exists")
    repos[name] = {'source': dict(source), 'status': 'maintained'}


def add_release_stanza(dist, repo, *, distro, url, version, packages=None):
    release = {
        'tags': {'release': release_tag_template(distro)},
        'url': url,
        'version': version,
    }
    if packages:
        release['packages'] = list(packages)
    dist['repositories'][repo]['release'] = release


def make_tracks(*, distro, vcs_uri, devel_branch, release_tag, push_url,
                actions):
    # release_inc 0 and no last_version: bloom then releases -1.
    return {'tracks': {distro: {
        'name': 'upstream',
        'vcs_type': 'git',
        'vcs_uri': vcs_uri,
        'devel_branch': devel_branch,
        'version': ':{auto}',
        'release_tag': release_tag,
        'ros_distro': distro,
        'release_repo_url': push_url,
        'release_inc': 0,
        'patches': None,
        'actions': list(actions),
    }}}


def release_version(tags, *, distro, package):
    prefix = f'release/{distro}/{package}/'
    versions = [t[len(prefix):] for t in tags if t.startswith(prefix)]
    if len(versions) != 1:
        raise ValueError(
            f"expected one '{prefix}*' tag, found {len(versions)}: {versions}")
    return versions[0]


def buildfarm_config(*, distro, rosdistro_index_url, ros_key, makeflags):
    index = {
        'type': 'buildfarm',
        'version': 1,
        'jenkins_url': 'http://127.0.0.1/unused',
        'prerequisites': {},
        'rosdistro_index_url': rosdistro_index_url,
        'distributions': {distro: {
            'release_builds': {'default': f'{distro}/release-build.yaml'},
        }},
    }
    release_build = {
        'type': 'release-build',
        'version': 2,
        'targets': {'ubuntu': {'resolute': {'amd64': {}}}},
        'repositories': {
            'keys': [ros_key],
            'urls': ['http://packages.ros.org/ros2/ubuntu'],
        },
        # colcon-ros-buildfarm points this at its local repository.
        'target_repository': 'http://127.0.0.1/unused',
        'upload_credential_id': 'unused',
        'build_environment_variables': {'MAKEFLAGS': makeflags},
    }
    return index, release_build


def check_pool(files, *, distro, packages):
    errors = []
    expected = {debian_name(distro, p) for p in packages}
    built = {'.dsc': {}, '_amd64.deb': {}}
    for name in files:
        for suffix in built:
            if name.endswith(suffix):
                built[suffix].setdefault(name.split('_', 1)[0], []).append(
                    name)
    for suffix, found in built.items():
        for deb in sorted(expected):
            if len(found.get(deb, [])) != 1:
                errors.append(
                    f'expected one {deb}*{suffix}, found {found.get(deb, [])}')
        for deb in sorted(set(found) - expected):
            errors.append(f'unexpected package: {found[deb]}')
    return errors


def _depends(control):
    match = re.search(r'^Depends:(.*)$', control, re.MULTILINE)
    if not match:
        return []
    return [d.strip().split(' ')[0] for d in match.group(1).split(',')
            if d.strip()]


def check_deb(*, control, paths, distro, parent, package, workspace_package):
    errors = []
    deb = debian_name(distro, package)
    prefix = f'./opt/ros/{distro}/'
    doc = f'./usr/share/doc/{deb}/'
    for path in paths:
        # dpkg-deb -c also lists the parent directories of every file.
        if not (path.startswith(prefix) or path.startswith(doc)
                or prefix.startswith(path) or doc.startswith(path)):
            errors.append(f'{deb}: file outside {prefix[1:]}: {path}')
    if package != workspace_package:
        depends = _depends(control)
        if not any(d.startswith(f'ros-{parent}-') for d in depends):
            errors.append(f'{deb}: no ros-{parent}-* in Depends: {depends}')
        workspace = debian_name(distro, workspace_package)
        if workspace not in depends:
            errors.append(f'{deb}: {workspace} not in Depends: {depends}')
    return errors


# Command line ------------------------------------------------------------


def _load(path):
    with open(path) as f:
        return yaml.safe_load(f)


def _dump(data, path):
    with open(path, 'w') as f:
        yaml.safe_dump(data, f, sort_keys=False)


def _dist_path(index_dir, distro):
    return os.path.join(index_dir, distro, 'distribution.yaml')


def _cmd_prepare_index(args, releases):
    distro = releases['distro']
    os.makedirs(os.path.join(args.out_dir, distro), exist_ok=True)
    shutil.copy(os.path.join(args.example_dir, 'index-v4.yaml'), args.out_dir)
    shutil.copy(os.path.join(args.example_dir, f'{distro}-cache.yaml.gz'),
                args.out_dir)
    dist = _load(_dist_path(args.example_dir, distro))
    for name, entry in releases['repositories'].items():
        if 'source' not in entry:
            continue
        add_repository(dist, name, entry['source'])
        add_release_stanza(dist, name, distro=distro,
                           url=f'{args.git_base}/{name}-release.git',
                           version=entry['version'])
    _dump(dist, _dist_path(args.out_dir, distro))
    return []


def _cmd_tracks(args, releases):
    # bloom prints a notice on stdout when imported; keep stdout for YAML.
    with contextlib.redirect_stdout(sys.stderr):
        from bloom.config import ACTION_LIST_HISTORY
    source = _load(args.dist_file)['repositories'][args.repo]['source']
    tracks = make_tracks(
        distro=releases['distro'], vcs_uri=source['url'],
        devel_branch=source['version'],
        release_tag=releases['repositories'][args.repo]['release_tag'],
        push_url=args.push_url, actions=ACTION_LIST_HISTORY[-1])
    yaml.safe_dump(tracks, sys.stdout, sort_keys=False)
    return []


def _cmd_add_stanza(args, releases):
    dist = _load(args.dist_file)
    add_release_stanza(dist, args.repo, distro=releases['distro'],
                       url=args.url, version=args.version)
    _dump(dist, args.dist_file)
    return []


def _cmd_release_version(args, releases):
    tags = sys.stdin.read().split()
    try:
        print(release_version(tags, distro=releases['distro'],
                              package=args.package))
    except ValueError as e:
        return [str(e)]
    return []


def _cmd_buildfarm_config(args, releases):
    distro = releases['distro']
    with open(args.ros_key) as f:
        ros_key = f.read()
    index, release_build = buildfarm_config(
        distro=distro, rosdistro_index_url=args.index_url, ros_key=ros_key,
        makeflags=args.makeflags)
    os.makedirs(os.path.join(args.out_dir, distro), exist_ok=True)
    _dump(index, os.path.join(args.out_dir, 'index.yaml'))
    _dump(release_build,
          os.path.join(args.out_dir, distro, 'release-build.yaml'))
    return []


def _pool_files(repo_base):
    files = []
    for root, _, names in os.walk(repo_base):
        files += [os.path.join(root, n) for n in names]
    return files


def _cmd_verify_pool(args, releases):
    names = [os.path.basename(f) for f in _pool_files(args.repo_base)]
    return check_pool(names, distro=releases['distro'],
                      packages=list(releases['repositories']))


def _cmd_verify_debs(args, releases):
    errors = []
    debs = [f for f in _pool_files(args.repo_base) if f.endswith('.deb')]
    by_name = {os.path.basename(f).split('_', 1)[0]: f for f in debs}
    for package in releases['repositories']:
        deb = by_name.get(debian_name(releases['distro'], package))
        if deb is None:
            errors.append(f'no .deb for {package}')
            continue
        control = subprocess.check_output(['dpkg-deb', '-f', deb], text=True)
        listing = subprocess.check_output(['dpkg-deb', '-c', deb], text=True)
        paths = [line.split()[5] for line in listing.splitlines() if line]
        errors += check_deb(
            control=control, paths=paths, distro=releases['distro'],
            parent=releases['parent'], package=package,
            workspace_package=releases['workspace_package'])
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--releases',
                        default=os.path.join(HERE, 'releases.yaml'))
    sub = parser.add_subparsers(dest='command', required=True)

    p = sub.add_parser('prepare-index')
    p.add_argument('example_dir')
    p.add_argument('out_dir')
    p.add_argument('--git-base', required=True)
    p.set_defaults(func=_cmd_prepare_index)

    p = sub.add_parser('tracks')
    p.add_argument('dist_file')
    p.add_argument('repo')
    p.add_argument('--push-url', required=True)
    p.set_defaults(func=_cmd_tracks)

    p = sub.add_parser('add-stanza')
    p.add_argument('dist_file')
    p.add_argument('repo')
    p.add_argument('--url', required=True)
    p.add_argument('--version', required=True)
    p.set_defaults(func=_cmd_add_stanza)

    p = sub.add_parser('release-version')
    p.add_argument('--package', required=True)
    p.set_defaults(func=_cmd_release_version)

    p = sub.add_parser('buildfarm-config')
    p.add_argument('out_dir')
    p.add_argument('--index-url', required=True)
    p.add_argument('--ros-key', required=True)
    p.add_argument('--makeflags', required=True)
    p.set_defaults(func=_cmd_buildfarm_config)

    for name, func in (('verify-pool', _cmd_verify_pool),
                       ('verify-debs', _cmd_verify_debs)):
        p = sub.add_parser(name)
        p.add_argument('repo_base')
        p.set_defaults(func=func)

    args = parser.parse_args(argv)
    errors = args.func(args, _load(args.releases))
    for error in errors:
        print(f'ERROR: {error}', file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
