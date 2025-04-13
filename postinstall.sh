#!/bin/sh

set -e

echo ">>> Updating system and installing Docker"
apk update && apk upgrade
apk add docker curl

echo ">>> Enabling and starting Docker service"
rc-update add docker default
service docker start

echo ">>> Creating Xen Orchestra data directory"
mkdir -p /opt/xoa-data

echo ">>> Pulling and running ronivay/xen-orchestra Docker container"
docker run -d \
  --name xen-orchestra \
  --restart unless-stopped \
  -p 80:80 \
  -v /opt/xoa-data:/data \
  ronivay/xen-orchestra

echo ">>> Installing Watchtower to auto-update Xen Orchestra"
docker run -d \
  --name watchtower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  xen-orchestra \
  --cleanup

echo "✅ Xen Orchestra is running on port 80"
ip addr show | grep 'inet ' | grep -v 127 | awk '{print $2}' | cut -d/ -f1

echo "💡 Open your browser to http://<this-vm-ip> to access XO"
