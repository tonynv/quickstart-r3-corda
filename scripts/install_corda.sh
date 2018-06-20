#!/bin/bash

set -euo pipefail

# Parameters

IP_ADDRESS=${1:-0.0.0.0}
COUNTRY_CODE=${2:-UK}
LOCATION=${3:-London}
DB_URL="$(echo "${4:-localhost}" | sed 's#/#\\/#g')" # TODO: Fix
DB_SCHEMA=${5:-CordaDB}
DB_USER=${6:-CordaUser}
DB_PWD=${7:-}
ONE_TIME_DOWNLOAD_KEY=${8:-}

# Constants

INSTALL_DIR="/opt/corda"
NODE_CONFIG_FILE="/opt/corda/node.conf"
VERSION=3.1-corda
TESTNET_URL="https://cces.corda.r3cev.com"

FLAVOUR="AWS"
DRIVER_FILE="postgresql-42.2.2.jar"
DRIVER_URL="https://jdbc.postgresql.org/download/$DRIVER_FILE"

# Helper functions

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $@"
}

download() {
    sudo curl -s -L "$1" -o "$INSTALL_DIR/$2"
}

error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') Error: $@" >> /dev/stderr
    exit 1
}

# Install dependencies

log "Installing on IP=${IP_ADDRESS} in location='${LOCATION}, ${COUNTRY_CODE}'"
log "Using database '${DB_URL}' with schema '${DB_SCHEMA}' and user '${DB_USER}'"

if [ -z "$ONE_TIME_DOWNLOAD_KEY" ]; then
    error "One time download key not provided"
fi

log "Using one time download key '${ONE_TIME_DOWNLOAD_KEY}''"

log "Installing dependencies ..."

sudo apt-get update -yqq
sudo apt-get install -yqq \
    apt-transport-https ca-certificates curl software-properties-common \
    openjdk-8-jdk unzip

# Install Corda

log "Installing Corda ..."

sudo adduser --system --no-create-home --group corda
sudo mkdir -p "$INSTALL_DIR"
sudo chown corda:corda "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR/cordapps"
sudo mkdir -p "$INSTALL_DIR/certificates"
sudo mkdir -p "$INSTALL_DIR/drivers"
cd "$INSTALL_DIR"

# Download driver JAR for MS SQL Server

log "Downloading JDBC database drivers ..."

download "$DRIVER_URL" "drivers/$DRIVER_FILE"

# Cache config file locally and patch it

log "Setting up node configuration and retrieving identity and truststore ..."

sudo curl -L \
    -d "{\"x500Name\":{\"locality\":\"$LOCATION\",\"country\":\"$COUNTRY_CODE\"},\"configType\":\"$FLAVOUR\"}" \
    -H "Content-Type: application/json" \
    -X POST "$TESTNET_URL/api/user/node/generate/one-time-key/redeem/$ONE_TIME_DOWNLOAD_KEY" \
    -o "$INSTALL_DIR/corda.zip" || error "Unable to download config template and truststore"

sudo unzip /opt/corda/corda.zip || error "Unable to unzip generated node bundle; was the correct one time download key used?"

log "Patching configuration file ..."

sudo sed -i "s/__IPADDRESS__/$IP_ADDRESS/g" "$NODE_CONFIG_FILE" || error "Failed to set IP address in config"
sudo sed -i "s/__DATASOURCE_URL__/jdbc:postgresql:\/\/$DB_URL/g" "$NODE_CONFIG_FILE" || error "Failed to set database URL in config"
sudo sed -i "s/__DATASOURCE_USER__/$DB_USER/g" "$NODE_CONFIG_FILE" || error "Failed to set database username in config"
sudo sed -i "s/__DATASOURCE_PASSWORD__/$DB_PWD/g" "$NODE_CONFIG_FILE" || error "Failed to set database password in config"
sudo sed -i "s/__DATABASE_SCHEMA_NAME__/$DB_SCHEMA/g" "$NODE_CONFIG_FILE" || error "Failed to set database schema name in config"

# TODO: Set if flavour is Enterprise (from redeem endpoint further up)
# sudo tee "$NODE_CONFIG_FILE" <<EOF
#     enterpriseConfiguration = {
#         mutualExclusionConfiguration = {
#             on = true
#             updateInterval = 20000
#             waitInterval = 40000
#         }
#     }
# EOF > /dev/null

log "Node configuration completed"

log "Installation complete"