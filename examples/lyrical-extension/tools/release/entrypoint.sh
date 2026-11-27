#!/bin/sh
# Put the REP 159 tools (rep159.repos) ahead of the stock ones, then run.
set -e
. /opt/rep159_ws/install/setup.sh
exec "$@"
