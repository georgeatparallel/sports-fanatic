#!/bin/sh
set -e

echo "Running migrations..."
bin/sports_fanatic eval "SportsFanatic.Release.migrate"

echo "Starting application..."
exec bin/sports_fanatic start
