#!/bin/bash

# Story Node Setup Script for Linux (Iliad Network)

# Set fixed download URLs
GETH_URL="https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz"
STORY_URL="https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.13-b4c7db1.tar.gz"

NETWORK="iliad"
NODE_MONIKER=""

# Function to display script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -m, --moniker MONIKER         Set node moniker"
    echo "  -h, --help                    Display this help message"
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--moniker)
            NODE_MONIKER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set data root directories
STORY_DATA_ROOT="$HOME/.story/story"
GETH_DATA_ROOT="$HOME/.story/geth"

# Create directories
mkdir -p "$STORY_DATA_ROOT"
mkdir -p "$GETH_DATA_ROOT"

# Download and install story-geth
echo "Downloading story-geth..."
curl -L -o geth.tar.gz "$GETH_URL"
tar -xzf geth.tar.gz
chmod +x geth
sudo mv geth /usr/local/bin/
rm geth.tar.gz

# Download and install story
echo "Downloading story..."
curl -L -o story.tar.gz "$STORY_URL"
tar -xzf story.tar.gz
chmod +x story
sudo mv story /usr/local/bin/
rm story.tar.gz

# Initialize story
if [ -n "$NODE_MONIKER" ]; then
    story init --network $NETWORK --moniker "$NODE_MONIKER"
else
    story init --network $NETWORK
fi

# Create systemd service files
echo "Creating systemd service files..."

# story-geth service
sudo tee /etc/systemd/system/story-geth.service > /dev/null << EOL
[Unit]
Description=Story-Geth
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=1
User=$USER
ExecStart=/usr/local/bin/geth --$NETWORK --syncmode full
StandardOutput=journal
StandardError=journal
SyslogIdentifier=story-geth
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOL

# story service
sudo tee /etc/systemd/system/story.service > /dev/null << EOL
[Unit]
Description=Story
After=network.target story-geth.service

[Service]
Type=simple
Restart=always
RestartSec=1
User=$USER
ExecStart=/usr/local/bin/story run
StandardOutput=journal
StandardError=journal
SyslogIdentifier=story
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable story-geth story
sudo systemctl start story-geth story

echo "Story node setup complete!"
echo "The services have been started automatically."
echo "You can check their status with:"
echo "  sudo systemctl status story-geth"
echo "  sudo systemctl status story"