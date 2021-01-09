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

# Add a user who will run node
pw useradd -n "$USER" -d /nonexistent -s /usr/sbin/nologin -c "User that runs Wiki.js"

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
sed -i '' -e "29s/.*/  user: $USER/" $DOCUMENTROOT/config.yml
sed -i '' -e "30s/.*/  pass: $PASS/" $DOCUMENTROOT/config.yml
sed -i '' -e "31s/.*/  db: $DB/" $DOCUMENTROOT/config.yml

# Apply the correct acces rights to our documentroot
chmod -R 750 $DOCUMENTROOT
chown -R $USER:wheel $DOCUMENTROOT

# Start Wiki.js
service wikijs start
