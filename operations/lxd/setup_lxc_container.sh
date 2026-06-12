#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

DEBUG=0
LXC_CONTAINER_NAME="Hiddify-on-LXC"
LXC_IMAGE="ubuntu:22.04"

# You may change any of the variables below, to change the port bound on your public/host IP.
# However this may cause failure to get SSL certificate.
HTTP_PORT_ON_HOST=80
HTTPS_PORT_ON_HOST=443
DIR_PATH=$(dirname "${BASH_SOURCE[0]}")/
REPO_ROOT="$(cd "${DIR_PATH}/../.." && pwd)"

if [ $DEBUG -eq 1 ]; then
  set -e
fi

# Install lxd based on the OS
install_lxd() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      debian)
        echo "Debian detected!"
	export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y lxd
        ;;
      ubuntu)
        echo "Ubuntu detected!"
	export DEBIAN_FRONTEND=noninteractive
	snap install lxd
	snap refresh lxd
	;;
      fedora)
        echo "Fedora detected!"
        dnf upgrade -y
        dnf install -y snapd
        systemctl enable --now snapd.socket
        ln -s /var/lib/snapd/snap /snap
        export PATH="$PATH:/snap/bin"
	snap wait system seed.loaded
        snap install lxd
        ;;
      almalinux|rocky)
        echo "AlmaLinux/Rocky detected!"
	dnf install -y epel-release
        dnf upgrade -y
        dnf install -y snapd
        systemctl enable --now snapd.socket
        ln -s /var/lib/snapd/snap /snap
        export PATH="$PATH:/snap/bin"
	snap wait system seed.loaded
        snap install lxd
        ;;
      *)
        echo "Unsupported OS for LXD installation: $ID"
	echo "Please install LXD manually and run the script again."
        exit 1
        ;;
    esac
  else
    echo "Unable to detect OS."
    echo "Please install LXD manually and run the script again."
    exit 1
  fi
}

# Fetch an Ubuntu 22.04 image and create a container
setup_container() {
  # Check if the container already exists
  if ! lxc info $LXC_CONTAINER_NAME &> /dev/null; then
    lxc init $LXC_IMAGE $LXC_CONTAINER_NAME
    lxc start $LXC_CONTAINER_NAME
   

    # Set up port forwarding
    lxc config device add $LXC_CONTAINER_NAME http     proxy   listen=tcp:0.0.0.0:$HTTP_PORT_ON_HOST connect=tcp:127.0.0.1:80
    lxc config device add $LXC_CONTAINER_NAME https    proxy   listen=tcp:0.0.0.0:$HTTPS_PORT_ON_HOST connect=tcp:127.0.0.1:443
    lxc config device add $LXC_CONTAINER_NAME httpsudp         proxy   listen=udp:0.0.0.0:$HTTPS_PORT_ON_HOST connect=udp:127.0.0.1:443

    configure_container_dns
    verify_container_dns

    configure_container_apt
    wait_for_container_apt
    sync_repo_into_container

    if [ $DEBUG -eq 1 ]; then
      lxc exec $LXC_CONTAINER_NAME -- bash -x -lc "cd /opt/hiddify-manager && export CREATE_EASYSETUP_LINK='true'; bash install.sh --no-gui"
    else
      lxc exec $LXC_CONTAINER_NAME -- bash -lc "cd /opt/hiddify-manager && export CREATE_EASYSETUP_LINK='true'; bash install.sh --no-gui"
    fi

    lxc exec "$LXC_CONTAINER_NAME" -- bash -lc '
      test -f /opt/hiddify-manager/current.json
      test -d /opt/hiddify-manager/log/system
    '
  else
    echo -e "Container $LXC_CONTAINER_NAME already exists.\n"
    echo "1. If you want to remap your Hiddify Manager's container ports to your pubic IP use the command:"
    echo -e "${GREEN}bash ${DIR_PATH}utils/lxc_ports_to_host.sh${NOCOLOR}\n"
    echo "2. If you want to delete a previously made container use the command:"
    echo -e "${GREEN}lxc delete $LXC_CONTAINER_NAME --force${NOCOLOR}" 
    exit 1
  fi
}

# Check if the container is running
verify_container() {
  if lxc info $LXC_CONTAINER_NAME | grep -q 'Status: RUNNING'; then
    echo "Container $LXC_CONTAINER_NAME is up and running."
  else
    echo "Failed to start container $LXC_CONTAINER_NAME."
    exit 1
  fi
}

configure_container_dns() {
  lxc exec "$LXC_CONTAINER_NAME" -- bash -lc '
    cat >/etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
  '
}

verify_container_dns() {
  lxc exec "$LXC_CONTAINER_NAME" -- bash -lc '
    for host in archive.ubuntu.com security.ubuntu.com github.com; do
      getent hosts "$host" >/dev/null 2>&1 && continue
      echo "Failed to resolve $host inside LXD container." >&2
      exit 1
    done
  '
}

configure_container_apt() {
  lxc exec "$LXC_CONTAINER_NAME" -- bash -lc '
    cat >/etc/apt/apt.conf.d/99force-ipv4 <<EOF
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
EOF
  '
}

wait_for_container_apt() {
  lxc exec "$LXC_CONTAINER_NAME" -- bash -lc '
    for attempt in $(seq 1 18); do
      if apt-get update; then
        exit 0
      fi

      echo "Attempt ${attempt}: apt-get update failed, waiting for container network..." >&2
      sleep 10
    done

    echo "Container apt network is not ready." >&2
    ip route >&2 || true
    exit 1
  '
}

sync_repo_into_container() {
  lxc exec "$LXC_CONTAINER_NAME" -- mkdir -p /opt/hiddify-manager
  tar \
    --exclude=.git \
    --exclude=.github \
    --exclude='__pycache__' \
    -C "$REPO_ROOT" \
    -cf - . | lxc exec "$LXC_CONTAINER_NAME" -- tar -xf - -C /opt/hiddify-manager
}

ensure_lxd_bridge() {
  if ! lxc network show lxdbr0 >/dev/null 2>&1; then
    lxc network create lxdbr0 ipv4.address=auto ipv4.nat=true ipv6.address=none
  fi

  if lxc profile device get default eth0 type >/dev/null 2>&1; then
    if lxc profile device get default eth0 nictype >/dev/null 2>&1; then
      lxc profile device unset default eth0 nictype || true
    fi
    if lxc profile device get default eth0 parent >/dev/null 2>&1; then
      lxc profile device unset default eth0 parent || true
    fi
    lxc profile device set default eth0 network lxdbr0
    lxc profile device set default eth0 name eth0
  else
    lxc profile device add default eth0 nic network=lxdbr0 name=eth0
  fi
}


# Main script execution

# Check the user 
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

if ! which lxd &> /dev/null; then
  echo "LXD not installed. I will install LXD..."
  install_lxd 
else
  echo "LXD already installed."
fi

if lxd init --dump | grep "networks: \[\]" &> /dev/null; then
  echo "Initializing LXD minimally..."
  lxd init --minimal
else
  echo "LXD seems to be already initialized."
fi

ensure_lxd_bridge

setup_container
verify_container

# Prints admin links
echo -e "\n\n\nYour admin links are printed. The ones that start with \`https\` should be preferred"
lxc exec $LXC_CONTAINER_NAME -- bash -c "cat /opt/hiddify-manager/current.json | jq -r '.panel_links[]'"

echo -e "\n\nIf you need TUI or shell for your container try:"
echo "${GREEN}lxc shell $LXC_CONTAINER_NAME${NOCOLOR}"

echo -e "${RED}WARNING!${NOCOLOR}\nCurrently your LXC container has no open ports on your host OS. For container ports to be seen you need to run ${GREEN}bash ${DIR_PATH}utils/lxc_ports_to_host.sh${NOCOLOR} each time that a new port is used by Hiddify Manager inside the container."
