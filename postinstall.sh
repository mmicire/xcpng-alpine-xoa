#!/bin/sh

set -e

echo ">>> Updating APK repositories..."

# Uncomment 'main' and 'community' repositories (http or https, Alpine-compatible)
sed -i '/^#http[s]*:\/\/dl-cdn\.alpinelinux\.org\/alpine\/.*\/main/s/^#//' /etc/apk/repositories
sed -i '/^#http[s]*:\/\/dl-cdn\.alpinelinux\.org\/alpine\/.*\/community/s/^#//' /etc/apk/repositories

apk update
apk upgrade --no-cache

echo ">>> Installing Docker and dependencies..."
apk add --no-cache docker docker-cli curl bash

echo ">>> Enabling and starting Docker..."
rc-update add docker boot
service docker start

echo ">>> Waiting for Docker daemon to start..."
for i in $(seq 1 10); do
  if docker info >/dev/null 2>&1; then
    echo "✅ Docker is ready."
    break
  fi
  echo "⏳ Waiting ($i)..."
  sleep 1
done

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon did not start in time."
  exit 1
fi

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

echo ">>> Installing Xen guest utilities for proper VM metrics/shutdown..."
apk add --no-cache xe-guest-utilities
rc-update add xe-guest-utilities default
/etc/init.d/xe-guest-utilities start

echo ">>> Setting up daily OS auto-updates with email alerts..."
apk add --no-cache msmtp mailx

# Basic msmtp config (you must update these for your SMTP provider!)
cat << 'EOF' > /etc/msmtprc
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.example.com
port           587
from           your@email.com
user           your@email.com
passwordeval   "cat /etc/msmtp-password"
EOF

chmod 600 /etc/msmtprc

# Example password file (protect this!)
echo "your-smtp-password" > /etc/msmtp-password
chmod 600 /etc/msmtp-password

# Configure mailx to use msmtp
echo "set sendmail=/usr/bin/msmtp" > /etc/mail.rc

# Enable and start cron
rc-update add crond
rc-service crond start

# Create daily auto-upgrade script
cat << 'EOF' > /etc/periodic/daily/auto-apk-upgrade
#!/bin/sh
LOGFILE=$(mktemp)
EMAIL="you@example.com"
SUBJECT="[Alpine VM] Package updates applied or error occurred"

apk update >> "$LOGFILE" 2>&1
apk upgrade --available --no-cache >> "$LOGFILE" 2>&1
RC=$?

if grep -q "Upgraded:" "$LOGFILE" || [ "$RC" -ne 0 ]; then
  cat "$LOGFILE" | mail -s "$SUBJECT" "$EMAIL"
fi

rm -f "$LOGFILE"
EOF

chmod +x /etc/periodic/daily/auto-apk-upgrade
echo "✅ Daily auto-update script installed. Will notify on updates or failures."

echo "⚠️  Manual configuration required:"
echo "   - /etc/msmtprc: update SMTP host, port, from, user"
echo "   - /etc/msmtp-password: store your SMTP password or app password"
echo "   - /etc/periodic/daily/auto-apk-upgrade: update the EMAIL variable"
echo "✅ Email notifications will only be sent on updates or errors."

XOA_IP=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
echo "✅ Postinstall complete. Xen Orchestra is running at: http://$XOA_IP"
