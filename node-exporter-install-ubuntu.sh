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

# Step 3: Create directory /etc/node-exporter if it doesn't exist
echo "Creating directory /etc/node-exporter if it doesn't exist..."
sudo mkdir -p /etc/node-exporter

# Step 4: Move files to /etc/node-exporter
echo "Moving Node Exporter files to /etc/node-exporter..."
sudo mv $NODE_EXPORTER/node_exporter /etc/node-exporter

# Step 5: Create Node Exporter service
echo "Creating Node Exporter service file..."
sudo bash -c 'cat > /etc/systemd/system/node-exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/etc/node-exporter/node_exporter
Restart=always
StandardOutput=append:/var/log/node_exporter.log
StandardError=append:/var/log/node_exporter.log

[Install]
WantedBy=multi-user.target
EOF'

# Step 6: Create log file and set permissions
echo "Creating log file for Node Exporter..."
sudo touch /var/log/node_exporter.log
sudo chmod 644 /var/log/node_exporter.log

# Step 7: Reload systemd and enable the Node Exporter service
echo "Reloading systemd and starting Node Exporter..."
sudo systemctl daemon-reload
sudo systemctl enable node-exporter
sudo systemctl restart node-exporter

# Step 8: Check if Node Exporter is running
echo "Checking Node Exporter status..."
sudo systemctl status node-exporter --no-pager

echo "Node Exporter setup completed!"
