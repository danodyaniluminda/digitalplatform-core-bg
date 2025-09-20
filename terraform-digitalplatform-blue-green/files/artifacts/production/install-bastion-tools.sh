#!/bin/bash

# Bastion Tools Installation Script
# This script can be run on a fresh EC2 instance to install all required tools

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    yum update -y
    
    # For Amazon Linux 2023, handle curl-minimal conflict and install python3-pip
    if grep -q "Amazon Linux release 2023" /etc/system-release 2>/dev/null; then
        log "Detected Amazon Linux 2023, handling curl conflict and installing dependencies..."
        # Force remove curl-minimal to avoid conflicts
        dnf remove -y curl-minimal --allowerasing 2>/dev/null || true
        rpm -e --nodeps curl-minimal 2>/dev/null || true
        
        # Install packages using dnf
        dnf install -y curl tar python3 git unzip wget python3-pip
        
        # Install Python Kubernetes library for Ansible k8s module
        pip3 install kubernetes PyYAML jsonpatch
    else
        # For other Amazon Linux versions
        yum install -y curl tar python3 git unzip wget python3-pip
        pip3 install kubernetes PyYAML jsonpatch
    fi
}

# Install Ansible and EPEL
install_ansible() {
    log "Installing Ansible..."
    
    # For Amazon Linux 2023, use dnf (no EPEL needed)
    if grep -q "Amazon Linux release 2023" /etc/system-release 2>/dev/null; then
        log "Detected Amazon Linux 2023, using dnf for Ansible installation..."
        dnf install -y ansible-core
    else
        # For Amazon Linux 2, use amazon-linux-extras
        log "Detected Amazon Linux 2, using amazon-linux-extras..."
        amazon-linux-extras install epel -y
        amazon-linux-extras install ansible2 -y
    fi
    
    if command -v ansible &> /dev/null; then
        info "Ansible installed successfully: $(ansible --version | head -n1)"
        
        # Install required Ansible collections for Kubernetes
        log "Installing Ansible collections..."
        if command -v ansible-galaxy &> /dev/null; then
            ansible-galaxy collection install kubernetes.core --force
            ansible-galaxy collection install community.general --force
            info "Ansible collections installed successfully"
        else
            warning "ansible-galaxy not found, skipping collection installation"
        fi
    else
        error "Ansible installation failed"
        exit 1
    fi
}

# Install kubectl
install_kubectl() {
    log "Installing kubectl..."
    
    if command -v kubectl &> /dev/null; then
        warning "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return 0
    fi
    
    cd /tmp
    curl -LO "https://dl.k8s.io/release/v1.32.3/bin/linux/amd64/kubectl"
    chmod +x kubectl
    
    if [ ! -f /usr/bin/kubectl ]; then
        install -o root -g root -m 0755 kubectl /usr/bin/kubectl
    fi
    
    # Verify installation
    if command -v kubectl &> /dev/null; then
        info "kubectl installed successfully: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    else
        error "kubectl installation failed"
        return 1
    fi
}

# Install AWS CLI v2
install_awscli() {
    log "Installing AWS CLI v2..."
    
    if command -v aws &> /dev/null; then
        current_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}')
        if [[ $current_version == *"aws-cli/2"* ]]; then
            warning "AWS CLI v2 is already installed: $current_version"
            return 0
        else
            warning "AWS CLI v1 detected, upgrading to v2..."
        fi
    fi
    
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    rm -rf aws awscliv2
    unzip -o awscliv2.zip
    ./aws/install --bin-dir /usr/bin --install-dir /usr/bin/aws-cli --update
    rm -rf awscliv2.zip aws
    
    # Verify installation
    if command -v aws &> /dev/null; then
        info "AWS CLI installed successfully: $(aws --version)"
    else
        error "AWS CLI installation failed"
        return 1
    fi
}

# Install Helm
install_helm() {
    log "Installing Helm..."
    
    if command -v helm &> /dev/null; then
        warning "Helm is already installed: $(helm version --short)"
        return 0
    fi
    
    cd /tmp
    wget https://get.helm.sh/helm-v3.17.2-linux-amd64.tar.gz
    tar -xzvf helm-v3.17.2-linux-amd64.tar.gz
    mv -f linux-amd64/helm /usr/bin/helm
    rm -rf helm-v3.17.2-linux-amd64.tar.gz linux-amd64
    
    # Verify installation
    if command -v helm &> /dev/null; then
        info "Helm installed successfully: $(helm version --short)"
    else
        error "Helm installation failed"
        return 1
    fi
}

# Install Velero
install_velero() {
    log "Installing Velero..."
    
    if command -v velero &> /dev/null; then
        warning "Velero is already installed: $(velero version --client-only)"
        return 0
    fi
    
    cd /tmp
    wget https://github.com/vmware-tanzu/velero/releases/download/v1.10.1-rc.1/velero-v1.10.1-rc.1-linux-amd64.tar.gz
    tar zxf velero-v1.10.1-rc.1-linux-amd64.tar.gz
    mv -f velero-v1.10.1-rc.1-linux-amd64/velero /usr/bin/
    rm -rf velero-v1.10.1-rc.1-linux-amd64* 
    
    # Verify installation
    if command -v velero &> /dev/null; then
        info "Velero installed successfully: $(velero version --client-only)"
    else
        error "Velero installation failed"
        return 1
    fi
}

# Create kubectl config directory
setup_kubectl_config() {
    log "Setting up kubectl configuration directories..."
    
    # Create .kube directory for root user
    mkdir -p /root/.kube
    chmod 755 /root/.kube
    
    # Create .kube directory for ec2-user
    if id "ec2-user" &>/dev/null; then
        mkdir -p /home/ec2-user/.kube
        chown ec2-user:ec2-user /home/ec2-user/.kube
        chmod 755 /home/ec2-user/.kube
    fi
    
    info "kubectl configuration directories created"
}

# Verify all installations
verify_installations() {
    log "Verifying all tool installations..."
    
    local tools=("kubectl" "aws" "helm" "velero" "ansible")
    local failed_tools=()
    
    echo -e "\n${GREEN}=== Tool Installation Verification ===${NC}"
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            case $tool in
                "kubectl")
                    version_output=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || echo "version check failed")
                    ;;
                "aws")
                    version_output=$(aws --version 2>/dev/null || echo "version check failed")
                    ;;
                "helm")
                    version_output=$(helm version --short 2>/dev/null || echo "version check failed")
                    ;;
                "velero")
                    version_output=$(velero version --client-only 2>/dev/null || echo "version check failed")
                    ;;
                "ansible")
                    version_output=$(ansible --version 2>/dev/null | head -n1 || echo "version check failed")
                    ;;
            esac
            echo -e "${GREEN}✓${NC} $tool: $version_output"
        else
            echo -e "${RED}✗${NC} $tool: not found"
            failed_tools+=("$tool")
        fi
    done
    
    if [ ${#failed_tools[@]} -eq 0 ]; then
        log "All tools installed successfully!"
        return 0
    else
        error "Failed to install: ${failed_tools[*]}"
        return 1
    fi
}

# Main execution
main() {
    log "Starting bastion tools installation..."
    
    check_permissions
    update_system
    install_ansible
    install_kubectl
    install_awscli
    install_helm
    install_velero
    setup_kubectl_config
    verify_installations
    
    log "Bastion tools installation completed successfully!"
    info "All tools are now available in /usr/bin/ and ready to use!"
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Bastion Tools Installation Script"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script installs essential tools on the bastion host:"
    echo "  - kubectl (Kubernetes CLI)"
    echo "  - aws (AWS CLI v2)"
    echo "  - helm (Kubernetes package manager)"
    echo "  - velero (Kubernetes backup tool)"
    echo "  - ansible (automation tool)"
    echo ""
    echo "The script must be run with sudo privileges."
    echo ""
    echo "Example:"
    echo "  sudo bash $0"
    exit 0
fi

# Execute main function
main "$@"
