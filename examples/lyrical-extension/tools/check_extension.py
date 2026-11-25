#!/usr/bin/env python3
"""Load a REP 159 child distribution and report what it adds to its parents.

Needs the REP 159 rosdistro (rep159.repos). Usage:

  check_extension.py INDEX_URL DISTRO [--repos-file FILE] [--expect-from-parent PKG ...]

It loads DISTRO with its parents merged, from the distribution file and from
the cache, then prints the repositories the child owns and where each
inherited one comes from. --repos-file writes a vcstool file with the
source entries of the child's own repositories. Exit status 1 when a check
fails.
"""

import argparse
import sys

import yaml
from rosdistro import get_cached_distribution
from rosdistro import get_distribution_file
from rosdistro import get_index


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('index_url')
    parser.add_argument('distro')
    parser.add_argument('--repos-file')
    parser.add_argument(
        '--expect-from-parent', nargs='*', default=[], metavar='PKG',
        help='release packages that must resolve to a binary_import parent')
    args = parser.parse_args(argv)

    index = get_index(args.index_url)
    dist_file = get_distribution_file(index, args.distro)
    if dist_file.version < 3:
        print('%s is a version %d file: no extends' % (args.distro, dist_file.version))
        return 1
    for ext in dist_file.extends:
        print('extends %s (%s) from %s' % (
            ext['distro_name'], ext['extension_method'],
            ext.get('index_url') or 'this index'))

    own = sorted(
        name for name, repo in dist_file.repositories.items()
        if getattr(repo, 'origin_distro', args.distro) == args.distro)
    inherited = {}
    for repo in dist_file.repositories.values():
        origin = getattr(repo, 'origin_distro', args.distro)
        if origin != args.distro:
            inherited[origin] = inherited.get(origin, 0) + 1
    print('%d repositories after the merge: %d own, %s' % (
        len(dist_file.repositories), len(own),
        ', '.join('%d from %s' % (n, o) for o, n in sorted(inherited.items()))))
    for name in own:
        repo = dist_file.repositories[name]
        src = repo.source_repository
        print('  own: %s%s%s' % (
            name,
            ' source %s@%s' % (src.url, src.version) if src else '',
            ' release %s' % repo.release_repository.version
            if repo.release_repository else ''))

    failed = False
    for pkg in args.expect_from_parent:
        rel = dist_file.release_packages.get(pkg)
        repo = dist_file.repositories.get(rel.repository_name) if rel else None
        origin = getattr(repo, 'origin_distro', None) if repo else None
        method = getattr(repo, 'extension_method', None) if repo else None
        ok = origin not in (None, args.distro) and method == 'binary_import'
        failed |= not ok
        print('%s %s: origin %s, %s' % ('OK  ' if ok else 'FAIL', pkg, origin, method))

    # The cache path is what rosdep and ros_buildfarm use: the child's cache
    # plus each parent's cache, loaded from the parent's index.
    dist = get_cached_distribution(index, args.distro)
    missing = [
        name for name in own
        if dist.repositories[name].source_repository
        and not dist.get_source_repo_package_xmls(name)]
    print('cache: %d repositories, %d release package.xmls, own source manifests %s' % (
        len(dist.repositories), len(dist.release_packages),
        'complete' if not missing else 'MISSING for %s' % ', '.join(missing)))
    failed |= bool(missing)

    if args.repos_file:
        repos = {}
        for name in own:
            src = dist_file.repositories[name].source_repository
            if src:
                repos[name] = {'type': src.type, 'url': src.url, 'version': src.version}
        with open(args.repos_file, 'w') as f:
            yaml.safe_dump({'repositories': repos}, f, default_flow_style=False)
        print('wrote %s (%d repositories)' % (args.repos_file, len(repos)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
