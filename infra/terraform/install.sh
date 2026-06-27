#!/bin/bash
# ==============================================================================
# Kubernetes Node Bootstrap Script
#
# Purpose:
#   Prepare an Ubuntu VM to become a Kubernetes control plane or worker node.
#
# This script DOES NOT:
#   - Initialize the Kubernetes cluster
#   - Join worker nodes
#   - Install a CNI plugin
#
# Those tasks should be handled later by Ansible.
# ==============================================================================

set -e

echo "======================================="
echo "Starting Kubernetes node bootstrap..."
echo "======================================="

# ------------------------------------------------------------------------------
# Update package lists and install latest security updates
# ------------------------------------------------------------------------------
apt-get update -y
apt-get upgrade -y

# ------------------------------------------------------------------------------
# Install common utilities used during administration and troubleshooting
# ------------------------------------------------------------------------------
apt-get install -y \
    curl \
    wget \
    vim \
    git \
    unzip \
    jq \
    net-tools \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    gnupg \
    lsb-release

# ------------------------------------------------------------------------------
# Disable swap
#
# Kubernetes requires swap to be disabled.
# The second command ensures swap remains disabled after reboot.
# ------------------------------------------------------------------------------
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# ------------------------------------------------------------------------------
# Load required kernel modules
# ------------------------------------------------------------------------------
cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ------------------------------------------------------------------------------
# Configure networking parameters required by Kubernetes
# ------------------------------------------------------------------------------
cat <<EOF >/etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sysctl --system

# ------------------------------------------------------------------------------
# Install containerd
#
# containerd is the recommended container runtime for Kubernetes.
# ------------------------------------------------------------------------------
apt-get install -y containerd

mkdir -p /etc/containerd

containerd config default >/etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# ------------------------------------------------------------------------------
# Add the Kubernetes package repository
# (Uses the pkgs.k8s.io repository for current Kubernetes releases.)
# ------------------------------------------------------------------------------
mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
| gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" \
> /etc/apt/sources.list.d/kubernetes.list

apt-get update

# ------------------------------------------------------------------------------
# Install Kubernetes components
# ------------------------------------------------------------------------------
apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

# Prevent Kubernetes packages from being upgraded accidentally
apt-mark hold kubelet kubeadm kubectl

# ------------------------------------------------------------------------------
# Enable services
# ------------------------------------------------------------------------------
systemctl enable containerd
systemctl enable kubelet

# ------------------------------------------------------------------------------
# Bootstrap complete
# ------------------------------------------------------------------------------
echo "======================================="
echo "Kubernetes node bootstrap completed."
echo "This node is ready for Ansible."
echo "======================================="