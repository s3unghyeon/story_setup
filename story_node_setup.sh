#!/bin/bash

# Exit on error
set -e

# Check if moniker is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <node_moniker>"
    exit 1
fi

moniker=$1

# Set up variables
GOVERSION="1.22.0"
GETH_VERSION="0.9.3-b224fdf"
STORY_VERSION="0.9.13-b4c7db1"

# Install required packages
echo "Installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install curl git jq build-essential gcc unzip wget lz4 -y

# Install Go
echo "Installing Go..."
cd ~
wget "https://golang.org/dl/go$GOVERSION.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$GOVERSION.linux-amd64.tar.gz"
rm "go$GOVERSION.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

# Install Story-Geth
echo "Installing Story-Geth..."
wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-$GETH_VERSION.tar.gz -O /tmp/geth-linux-amd64-$GETH_VERSION.tar.gz
tar -xzf /tmp/geth-linux-amd64-$GETH_VERSION.tar.gz -C /tmp
mkdir -p ~/go/bin
sudo cp /tmp/geth-linux-amd64-$GETH_VERSION/geth ~/go/bin/story-geth

# Install Story binary
echo "Installing Story binary..."
wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-$STORY_VERSION.tar.gz -O /tmp/story-linux-amd64-$STORY_VERSION.tar.gz
tar -xzf /tmp/story-linux-amd64-$STORY_VERSION.tar.gz -C /tmp
mkdir -p ~/.story/story/cosmovisor/genesis/bin
sudo cp /tmp/story-linux-amd64-$STORY_VERSION/story ~/.story/story/cosmovisor/genesis/bin/story

# Install Cosmovisor
echo "Installing Cosmovisor..."
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

# Setup Cosmovisor
echo "Setting up Cosmovisor..."
mkdir -p ~/.story/story/cosmovisor
echo "export DAEMON_NAME=story" >> ~/.bash_profile
echo "export DAEMON_HOME=$HOME/.story/story" >> ~/.bash_profile
echo "export PATH=$HOME/go/bin:$DAEMON_HOME/cosmovisor/current/bin:$PATH" >> ~/.bash_profile
source ~/.bash_profile

# Initialize Story node
echo "Initializing Story node..."
~/.story/story/cosmovisor/genesis/bin/story init --network iliad --moniker "$moniker"

# Update peers
echo "Updating peers..."
PEERS=$(curl -sS https://story-testnet-rpc.blockhub.id/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.story/story/config/config.toml

# Create Story-Geth service
echo "Creating Story-Geth service..."
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Create Story service
echo "Creating Story service..."
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Cosmovisor service for Story binary
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/cosmovisor run run
WorkingDirectory=$HOME/.story/story
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
Environment="DAEMON_NAME=story"
Environment="DAEMON_HOME=$HOME/.story/story"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=$HOME/.story/story/data"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable story-geth story
sudo systemctl start story-geth
sudo systemctl start story

# Clean up
rm -rf /tmp/geth-linux-amd64-$GETH_VERSION /tmp/story-linux-amd64-$STORY_VERSION
rm /tmp/geth-linux-amd64-$GETH_VERSION.tar.gz /tmp/story-linux-amd64-$STORY_VERSION.tar.gz

echo "Installation complete."