#!/bin/bash

# Function to display menu and get user choice
choose_snapshot_type() {
    echo "Choose snapshot type:"
    echo "1. Pruned snapshot"
    echo "2. Archive snapshot"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1) 
            echo "Pruned snapshot selected."
            SNAPSHOT_TYPE="pruned"
            ;;
        2) 
            echo "Archive snapshot selected."
            SNAPSHOT_TYPE="archive"
            ;;
        *) 
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Function to set download URLs based on snapshot type
set_download_urls() {
    GETH_URL="https://story-testnet.nodeinfra.com/snapshot/$SNAPSHOT_TYPE/geth_snapshot.lz4"
    STORY_URL="https://story-testnet.nodeinfra.com/snapshot/$SNAPSHOT_TYPE/story_snapshot.lz4"
}

# Main script starts here
choose_snapshot_type
set_download_urls

# Install required dependencies
sudo apt-get install wget lz4 -y

# Stop story-geth and story nodes
sudo systemctl stop story-geth
sudo systemctl stop story

# Back up validator state
sudo cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup

# Delete previous geth chaindata and story data folders
sudo rm -rf $HOME/.story/geth/iliad/geth/chaindata
sudo rm -rf $HOME/.story/story/data

# Download story-geth and story snapshots
wget -O geth_snapshot.lz4 $GETH_URL
wget -O story_snapshot.lz4 $STORY_URL

# Decompress story-geth and story snapshots
lz4 -c -d geth_snapshot.lz4 | sudo tar -xv -C $HOME/.story/geth/iliad/geth
lz4 -c -d story_snapshot.lz4 | sudo tar -xv -C $HOME/.story/story

# Delete downloaded story-geth and story snapshots
sudo rm -v geth_snapshot.lz4
sudo rm -v story_snapshot.lz4

# Restore your validator state
sudo cp $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

# Start your story-geth and story nodes
sudo systemctl start story-geth
sudo systemctl start story

echo "Story node setup complete with $SNAPSHOT_TYPE snapshot."