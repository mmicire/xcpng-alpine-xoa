#!/bin/sh

set -e

echo ">>> Updating APK repositories..."

# Uncomment main and community repos if commented out
sed -i 's|^#\(https://dl-cdn.alpinelinux.org/alpine/v[0-9]\+\.[0-9]\+/main\)|\1|' /etc/apk/repositories
sed -i 's|^#\(https://dl-cdn.alpinelinux.org/alpine/v[0-9]\+\.[0-9]\+/community\)|\1|' /etc/apk/repositories

apk update
apk upgrade --no-cache

echo ">>> Installing Docker and dependencies..."
apk add --no-cache docker docker-cli curl bash

echo ">>> Enabling and starting Docker..."
rc-update add docker boot
service docker start

echo ">>> Pulling Xen Orchestra Docker image..."
docker pull ronivay/xen-orchestra

echo ">>> Starting Xen Orchestra container..."
docker run -d \
  --name xoa \
  -p 80:80 \
  -v /var/lib/xoa:/data \
  --restart unless-stopped \
  ronivay/xen-orchestra

echo ">>> Installing Watchtower for automatic updates..."
docker pull containrrr/watchtower

docker run -d \
  --name watchtower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --cleanup --interval 3600

echo "✅ Postinstall complete. Xen Orchestra is running on port 80."
