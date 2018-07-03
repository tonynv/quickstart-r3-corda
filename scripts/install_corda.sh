#!/bin/bash

set -euo pipefail

# Parameters

IP_ADDRESS="${1:-}"
COUNTRY_CODE="$(echo "${2:-GB}" | sed 's/[^A-Za-z]//g')"
LOCATION="$(echo "${3:-London}" | sed 's/[^A-Za-z -]//g')"
DB_URL="${4:-}"
DB_SCHEMA="public"
DB_USER="${5:-CordaUser}"     # Constrained by template
DB_PWD="${6:-}"               # Constrained by template
ONE_TIME_DOWNLOAD_KEY="$(echo "${7:-}" | sed 's/[^A-Za-z0-9-]//g')"
RPC_IP="$(echo "${8:-}" | sed 's#/.*$##')"

# Constants

INSTALL_DIR="/opt/corda"
NODE_CONFIG_FILE="/opt/corda/node.conf"

TESTNET_URL="https://testnet.corda.network"

PLATFORM="AWS"
DISTRO="ENTERPRISE"

DRIVER_FILE="postgresql-42.2.2.jar"
DRIVER_URL="https://jdbc.postgresql.org/download/$DRIVER_FILE"

# Helper functions

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $@"
}

download() {
    sudo curl -s -L "$1" -o "$INSTALL_DIR/$2"
}

error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $@" >> /dev/stderr
    exit 1
}

# Fail fast if one-time-key has not been set

log "Installing on IP=${IP_ADDRESS} in location='${LOCATION}, ${COUNTRY_CODE}' ..."
log "Using database '${DB_URL}' with schema '${DB_SCHEMA}' and user '${DB_USER}' ..."

if [ -z "$ONE_TIME_DOWNLOAD_KEY" ]; then
    error "One time download key not provided"
fi

log "Using one time download key '${ONE_TIME_DOWNLOAD_KEY}' ..."

# Install dependencies

log "Updating package manager cache ..."

sudo apt-get update -yqq

log "Installing dependencies ..."

sudo apt-get install -yqq \
    apt-transport-https ca-certificates curl software-properties-common \
    openjdk-8-jdk unzip

# Set up Corda installation directory

log "Installing Corda into '$INSTALL_DIR' ..."

sudo adduser --system --no-create-home --group corda
sudo mkdir -p "$INSTALL_DIR"
sudo chown corda:corda "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR/cordapps"
sudo mkdir -p "$INSTALL_DIR/certificates"
sudo mkdir -p "$INSTALL_DIR/drivers"
cd "$INSTALL_DIR"

# Download and install database driver JAR

log "Downloading JDBC database driver ..."

download "$DRIVER_URL" "drivers/$DRIVER_FILE"

log "Installed JDBC database driver '$DRIVER_FILE'"

# Download configuration, identity, truststore and binaries

log "Retrieving configuration file, identity, truststore and binaries from '$TESTNET_URL' for distribution '$DISTRO' ..."

sudo curl -L -s \
    -d "{\"x500Name\":{\"locality\":\"$LOCATION\",\"country\":\"$COUNTRY_CODE\"},\"configType\":\"$PLATFORM\",\"distribution\":\"$DISTRO\"}" \
    -H "Content-Type: application/json" \
    -X POST "$TESTNET_URL/api/user/node/generate/one-time-key/redeem/$ONE_TIME_DOWNLOAD_KEY" \
    -o "$INSTALL_DIR/corda.zip" || error "Unable to download config template and truststore"

log "Distribution bundle stored to '$INSTALL_DIR/corda.zip'"

log "Unpacking distribution ..."

sudo unzip /opt/corda/corda.zip 2> /dev/null || error "Unable to unzip generated node bundle; was the correct one time download key used?"

log "Setting permissions for node directories ..."

sudo chown -R corda:corda certificates
sudo chown -R corda:corda cordapps

log "Patching configuration file ..."

ESC_DB_URL="$(echo "$DB_URL" | sed 's#/#\\/#g')"
sudo sed -i "/p2pAddress/s/__IPADDRESS__/$IP_ADDRESS/g" "$NODE_CONFIG_FILE" || error "Failed to set P2P IP address in config"
sudo sed -i "/address/s/__IPADDRESS__/$RPC_IP/g" "$NODE_CONFIG_FILE" || error "Failed to set RPC IP address in config"
sudo sed -i "/adminAddress/s/__IPADDRESS__/$RPC_IP/g" "$NODE_CONFIG_FILE" || error "Failed to set RPC admin IP address in config"
sudo sed -i "s/__DATASOURCE_URL__/jdbc:postgresql:\/\/$ESC_DB_URL/g" "$NODE_CONFIG_FILE" || error "Failed to set database URL in config"
sudo sed -i "s/__DATASOURCE_USER__/$DB_USER/g" "$NODE_CONFIG_FILE" || error "Failed to set database username in config"
sudo sed -i "s/__DATASOURCE_PASSWORD__/$DB_PWD/g" "$NODE_CONFIG_FILE" || error "Failed to set database password in config"
sudo sed -i "s/__DATABASE_SCHEMA_NAME__/$DB_SCHEMA/g" "$NODE_CONFIG_FILE" || error "Failed to set database schema name in config"
sudo sed -i "s/^[ ]*\"extraAdvertisedServiceIds\".*$//" "$NODE_CONFIG_FILE" || error "Failed to remove 'extraAdvertisedServiceIds' config"
sudo sed -i "s/^[ ]*\"webAddress\".*$//" "$NODE_CONFIG_FILE" || error "Failed to remove 'webAddress' config"

log "Node configuration completed"

log "Installation successfully completed"
