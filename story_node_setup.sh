#!/bin/bash

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a story_node_setup.log
}

# Function to check command success
check_success() {
    if [ $? -ne 0 ]; then
        log "Error: $1"
        exit 1
    fi
}

# Function to display the main menu
display_menu() {
    clear
    echo "Story Node Setup and Management Script"
    echo "1. Install Story Node"
    echo "2. Upgrade Story Node"
    echo "3. Check Current Version"
    echo "4. Check Node Status"
    echo "5. Exit"
    echo -n "Please enter your choice: "
}


# Function to install Story Node
setup_node() {
    log "Starting Story Node installation..."
    read -p "Enter your node moniker: " moniker

    # Install Go
    cd ~ && ver="1.22.0" && wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
    check_success "Failed to download Go"
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
    check_success "Failed to install Go"
    rm "go$ver.linux-amd64.tar.gz"
    echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
    source ~/.bash_profile
    go version
    check_success "Failed to set up Go"

    # Install Story Geth
    wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.3-b224fdf.tar.gz -O /tmp/geth-linux-amd64-0.9.3-b224fdf.tar.gz
    check_success "Failed to download Story Geth"
    tar -xzf /tmp/geth-linux-amd64-0.9.3-b224fdf.tar.gz -C /tmp
    mkdir -p ~/go/bin
    sudo cp /tmp/geth-linux-amd64-0.9.3-b224fdf/geth ~/go/bin/story-geth
    check_success "Failed to install Story Geth"

    # Install Story binary
    wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.13-b4c7db1.tar.gz -O /tmp/story-linux-amd64-0.9.13-b4c7db1.tar.gz
    check_success "Failed to download Story binary"
    tar -xzf /tmp/story-linux-amd64-0.9.13-b4c7db1.tar.gz -C /tmp
    mkdir -p ~/.story/story/cosmovisor/genesis/bin
    sudo cp /tmp/story-linux-amd64-0.9.13-b4c7db1/story ~/.story/story/cosmovisor/genesis/bin/story
    check_success "Failed to install Story binary"

    # Install Cosmovisor
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
    check_success "Failed to install Cosmovisor"
    mkdir -p ~/.story/story/cosmovisor
    echo "export DAEMON_NAME=story" >> ~/.bash_profile
    echo "export DAEMON_HOME=$HOME/.story/story" >> ~/.bash_profile
    echo "export PATH=$HOME/go/bin:$DAEMON_HOME/cosmovisor/current/bin:$PATH" >> ~/.bash_profile
    source ~/.bash_profile

    # Initialize Story node
    ~/.story/story/cosmovisor/genesis/bin/story init --network iliad --moniker "$moniker"
    check_success "Failed to initialize Story node"

    # Update peers
    log "Updating peers..."
    PEERS=$(curl -sS https://story-testnet-rpc.blockhub.id/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
    sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.story/story/config/config.toml
    check_success "Failed to update peers"

    # Set up systemd services
    sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target
[Service]
User=$USER
ExecStart=/home/ubuntu/go/bin/story-geth --iliad --syncmode full --http --http.api eth,net,web3,engine --http.vhosts '*' --http.addr 0.0.0.0 --http.port 8545 --ws --ws.api eth,web3,net,txpool --ws.addr 0.0.0.0 --ws.port 8546
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    check_success "Failed to create story-geth service"

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
    check_success "Failed to create story service"

    sudo systemctl daemon-reload
    sudo systemctl enable story-geth story
    sudo systemctl start story-geth story
    check_success "Failed to start services"

    log "Story Node installed successfully"
}

# Function to upgrade Story Node
upgrade_node() {
    log "Starting Story Node upgrade process..."
    read -p "Enter the new Story binary download link: " download_link
    read -p "Enter the new Story version (e.g., v0.10.1): " new_version
    
    # Confirm upgrade
    read -p "Are you sure you want to upgrade to version $new_version? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        log "Upgrade cancelled"
        return
    fi

    # Backup current configuration
    backup_dir="$HOME/.story/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r $HOME/.story/story/config "$backup_dir"
    log "Current configuration backed up to $backup_dir"
    
    # Create a temporary directory for the download
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Download and extract the new Story binary
    log "Downloading and extracting the new Story binary..."
    curl -L "$download_link" | tar -xz
    check_success "Failed to download or extract new Story binary"
    
    # Find the story executable
    story_executable=$(find . -type f -executable -name "story" | head -n 1)
    
    if [ -z "$story_executable" ]; then
        log "Error: No 'story' executable found in the downloaded archive."
        cd - > /dev/null
        rm -rf "$temp_dir"
        return
    fi
    
    # Get the full path of the story executable
    story_path=$(readlink -f "$story_executable")
    
    # Use Cosmovisor to add the upgrade
    log "Scheduling the upgrade..."
    cosmovisor add-upgrade "$new_version" "$story_path"
    check_success "Failed to schedule upgrade"
    
    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log "Upgrade to version $new_version scheduled successfully."
}

# Function to check current version
check_version() {
    if [ -f "$HOME/.story/story/cosmovisor/current/bin/story" ]; then
        current_version=$($HOME/.story/story/cosmovisor/current/bin/story version 2>&1)
        if [ $? -eq 0 ]; then
            log "Current Story version:"
            echo "$current_version"
        else
            log "Error: Unable to determine current Story version. Error message:"
            echo "$current_version"
        fi
    else
        log "Error: Story binary not found. Is Story node installed correctly?"
    fi
}

check_node_status() {
    echo "Choose a service to check:"
    echo "1. story-geth"
    echo "2. story"
    read -p "Enter your choice (1 or 2): " service_choice

    case $service_choice in
        1)
            log "Checking story-geth status..."
            sudo journalctl -u story-geth -n 10 --no-pager
            ;;
        2)
            log "Checking story status..."
            sudo journalctl -u story -n 10 --no-pager
            ;;
        *)
            log "Invalid choice. Please try again."
            ;;
    esac
}

# Main script
while true; do
    display_menu
    read choice
    case $choice in
        1)
            setup_node
            ;;
        2)
            upgrade_node
            ;;
        3)
            check_version
            ;;
        4)
            check_node_status
            ;;
        5)
            log "Exiting the script. Goodbye!"
            exit 0
            ;;
        *)
            log "Invalid option, please try again."
            ;;
    esac
    echo -e "\nPress Enter to continue..."
    read
done