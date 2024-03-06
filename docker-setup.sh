#!/bin/bash
echo " "
echo "OS Checker...."
# Check if the OS is Ubuntu
if [[ $(uname -s) == "Linux" && -f /etc/os-release && $(grep -E '^ID="?(ubuntu|debian)"?' /etc/os-release) ]]; then
    echo "The OS is Ubuntu. Proceeding with next steps..."
else
    echo "This script requires Ubuntu. Exiting."
    exit 1
fi

sleep 2
echo " "
echo " "

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

cat <<EOF > /etc/docker/daemon.json
{
    "bip": "172.172.0.1/16"
}
EOF

systemctl enable docker
systemctl restart docker
echo " "
echo "======================================="
echo "Installation Finish - BIP 172.172.0.0/16"

docker -v


docker compose version
echo "======================================="
