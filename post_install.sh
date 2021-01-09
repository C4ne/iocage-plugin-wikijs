#!/bin/sh
# Let installation fail if any of these fail
set -e 

# Enable the services
sysrc -f /etc/rc.conf postgresql_enable=YES
sysrc -f /etc/rc.conf wikijs_enable=YES

# Start postgres
service postgresql initdb
service postgresql start

USER="wikijs"
DB="wikijs_production"
DOCUMENTROOT="/usr/local/www/wikijs"
INTERFACE="$(route get default | awk '$1 == "interface:" {print $2}')"
IPV4="$(ifconfig $if | awk '$1 == "inet" {print $2}')"
SSL_KEY="/etc/ssl/private/key.pem"
SSL_CERT="/etc/ssl/certs/cert.pem"

if ! route get "$IPV4"; then
    echo "IP address \'$IPV4\' doesn't seem to be valid"
    exit 1
fi

# Add a user who will run node
pw useradd -n "$USER" -d /nonexistent -s /usr/sbin/nologin -c "User that runs Wiki.js"

# Generate SSL certificate and key
mkdir /etc/ssl/private
chmod -R 755 /etc/ssl/private
openssl req -nodes -x509 -newkey rsa:4096 -keyout $SSL_KEY \
  -out $SSL_CERT -days 365\
  -subj "/C=DE/ST=Berlin/L=Berlin/O=BND/OU=Abteilung 8/"
chmod 400 "$SSL_KEY"
chmod 400 "$SSL_CERT"
chown wikijs "$SSL_KEY"
chown wikijs "$SSL_CERT"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser

# Generate the password
export LC_ALL=C
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 > /root/dbpassword
PASS=`cat /root/dbpassword`

# Create database and user
psql -d template1 -U postgres -c "CREATE USER ${USER} CREATEDB SUPERUSER;"
psql -d template1 -U postgres -c "CREATE DATABASE ${DB} OWNER ${USER};"
psql -d template1 -U postgres -c "ALTER USER ${USER} WITH PASSWORD '${PASS}';"

# Postgresql must be restarted after config change
service postgresql restart

# Get Wiki.js
fetch https://github.com/Requarks/wiki/releases/download/2.5.170/wiki-js.tar.gz

# Decrompress Wiki.js
mkdir -p $DOCUMENTROOT
tar xzf wiki-js.tar.gz -C $DOCUMENTROOT

# Configure Wiki.js
cp -p $DOCUMENTROOT/config.sample.yml $DOCUMENTROOT/config.yml

# Enable DB access for Wiki.js
sed -i '' -e "29s/.*/  user: $USER/" $DOCUMENTROOT/config.yml
sed -i '' -e "30s/.*/  pass: $PASS/" $DOCUMENTROOT/config.yml
sed -i '' -e "31s/.*/  db: $DB/" $DOCUMENTROOT/config.yml

# Enable and configure SSL
sed -i '' -e "61s/.*/  enabled: true" $DOCUMENTROOT/config.yml
sed -i '' -e "71s/.*/  key: $SSL_KEY" $DOCUMENTROOT/config.yml
sed -i '' -e "61s/.*/  cert: $SSL_CERT" $DOCUMENTROOT/config.yml

# Make Wiki.js bind to the current IP
sed -i '' -e "99s/.*/bindIP: $IPV4" $DOCUMENTROOT/config.yml

# Apply the correct acces rights to our documentroot
chmod -R 750 $DOCUMENTROOT
chown -R $USER:wheel $DOCUMENTROOT

# Start Wiki.js
service wikijs start
