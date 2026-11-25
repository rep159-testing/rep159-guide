#!/usr/bin/env bash
# Rebuild my-extended-distro-cache.yaml.gz. Needs the REP 159 rosdistro
# (rep159.repos) and network access: the cache holds the package.xml of every source and
# release entry of the child, fetched from their repositories.
# --preclean stores the child's distribution file unmerged; the parent's
# cache is merged in when the child's cache is loaded.
set -euo pipefail
cd "$(dirname "$0")/.."
DISTROS=(my-extended-distro)

python3 -m rosdistro.cli.rosdistro_build_cache --preclean --include-source \
    index-v4.yaml "${DISTROS[@]}"
# rosdistro_build_cache stamps the current time in the gzip header;
# recompress without it so an unchanged cache gives an unchanged file.
for name in "${DISTROS[@]}"; do
    gzip -n -9 -c "$name-cache.yaml" > "$name-cache.yaml.gz"
done
