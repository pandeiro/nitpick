#!/bin/sh
set -e

echo "Installing dependencies..."
nimble install -y --depsOnly

echo "Building Nitpick..."
nimble build -d:debug --mm:refc
nimble scss
nimble md

if [ ! -f nitter.conf ]; then
    echo "Creating nitter.conf from example..."
    cp nitter.example.conf nitter.conf
    # Automatically set redisHost for docker-compose
    sed -i 's/redisHost = "localhost"/redisHost = "nitter-redis"/' nitter.conf
fi

echo "Starting Nitpick..."
./nitter
