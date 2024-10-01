#!/bin/bash

# Set Node Exporter version
VERSION="1.8.2"
NODE_EXPORTER="node_exporter-$VERSION.linux-amd64"

# Step 1: Download Node Exporter
echo "Downloading Node Exporter version $VERSION..."
wget https://github.com/prometheus/node_exporter/releases/download/v$VERSION/$NODE_EXPORTER.tar.gz

# Step 2: Extract Files
echo "Extracting Node Exporter files..."
tar xzf $NODE_EXPORTER.tar.gz

# Remove tar.gz file after extraction
rm -rf $NODE_EXPORTER.tar.gz

# Step 3: Move files to /etc/node_exporter
echo "Moving Node Exporter files to /etc/node_exporter..."
sudo mv $NODE_EXPORTER /etc/node_exporter

# Step 4: Create Node Exporter service
echo "Creating Node Exporter service file..."
sudo bash -c 'cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/etc/node_exporter/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

# Step 5: Reload systemd and enable the Node Exporter service
echo "Reloading systemd and starting Node Exporter..."
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter

# Step 6: Check if Node Exporter is running
echo "Checking Node Exporter status..."
sudo systemctl status node_exporter --no-pager

echo "Node Exporter setup completed!"
