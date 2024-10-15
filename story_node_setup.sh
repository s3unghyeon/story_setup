install_story_node() {
    read -p "Enter your node moniker: " moniker


    cd ~ && ver="1.22.0" && wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz" && \
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz" && \
    rm "go$ver.linux-amd64.tar.gz" && echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile && source ~/.bash_profile && go version

    wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.3-b224fdf.tar.gz -O /tmp/geth-linux-amd64-0.9.3-b224fdf.tar.gz
    tar -xzf /tmp/geth-linux-amd64-0.9.3-b224fdf.tar.gz -C /tmp
    mkdir -p ~/go/bin
    sudo cp /tmp/geth-linux-amd64-0.9.3-b224fdf/geth ~/go/bin/story-geth

    wget -q https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.13-b4c7db1.tar.gz -O /tmp/story-linux-amd64-0.9.13-b4c7db1.tar.gz
    tar -xzf /tmp/story-linux-amd64-0.9.13-b4c7db1.tar.gz -C /tmp
    mkdir -p ~/.story/story/cosmovisor/genesis/bin
    sudo cp /tmp/story-linux-amd64-0.9.13-b4c7db1/story ~/.story/story/cosmovisor/genesis/bin/story

    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

    mkdir -p ~/.story/story/cosmovisor
    echo "export DAEMON_NAME=story" >> ~/.bash_profile
    echo "export DAEMON_HOME=$HOME/.story/story" >> ~/.bash_profile
    echo "export PATH=$HOME/go/bin:$DAEMON_HOME/cosmovisor/current/bin:$PATH" >> ~/.bash_profile
    source ~/.bash_profile

    ~/.story/story/cosmovisor/genesis/bin/story init --network iliad --moniker "$moniker"

    echo "Updating peers..."
    sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.story/story/config/config.toml

    sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=$USER
ExecStart=/home/ubuntu/go/bin/story-geth --iliad --syncmode full --http --http.api eth,net,web3,engine --http.vhosts '*' --http.addr 0.0.0.0 --http.port 8545 --ws --ws.api eth,web3,net,txpool --ws.addr 0.0.0.0 --ws.port 8546Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # Step 10: Create and Configure systemd Service for Cosmovisor (Story)
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

    # Step 11: Reload systemd, Enable, and Start Services
    sudo systemctl daemon-reload
    sudo systemctl enable story-geth story
    sudo systemctl start story-geth story

    echo -e "installed successfully"

}

check_logs() {
    echo -e "\nCheck Story logs"
    sudo journalctl -u story -o cat -n 50
    echo -e "\nCheck Story-Geth logs"
    sudo journalctl -u story-geth -o cat -n 50
}

check_sync_status() {
    echo -e "\nCheck node sync status..."
    local_height=$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height')
    network_height=$(curl -s https://story-testnet-rpc.blockhub.id/status | jq -r '.result.sync_info.latest_block_height')
    blocks_left=$((network_height - local_height))

    echo -e "\033[1;32mYour node height:\033[0m \033[1;34m$local_height\033[0m" \
            "| \033[1;33mNetwork height:\033[0m \033[1;36m$network_height\033[0m" \
            "| \033[1;37mBlocks left:\033[0m \033[1;31m$blocks_left\033[0m"
}

run_story_node_setup() {
    echo "Starting Story Node setup and checks..."
    
    install_story_node
    echo "Waiting for services to start up..."
    sleep 15 
    
    check_logs
    echo "Logs checked. Waiting before sync status check..."
    sleep 10  
    
    check_sync_status
    echo "Setup and checks completed."
}

run_story_node_setup