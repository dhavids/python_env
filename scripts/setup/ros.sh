# This script will setup ROS (Robot Operating System) or ROS2 environment.
# By default, it sets up ROS Humble for Ubuntu 22.04.
# If --noetic flag is provided, it sets up ROS Noetic for Ubuntu 20.04.
# It verifies the Ubuntu version and ROS versions before proceeding.

#!/bin/bash
set -e

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

# Detect if we need sudo (not in Docker or running as root)
if [ "$EUID" -eq 0 ] || ! command -v sudo &> /dev/null; then
    SUDO=""
    echo "[INFO] Running without sudo (Docker or root user)"
else
    SUDO="sudo"
fi

ROS_VERSION="humble"

# Get Ubuntu version - install lsb_release if not available (common in Docker)
if ! command -v lsb_release &> /dev/null; then
    echo "[INFO] lsb_release not found, installing..."
    $SUDO apt update && $SUDO apt install -y lsb-release
fi

UBUNTU_VERSION=$(lsb_release -rs)

if [[ "$UBUNTU_VERSION" == "22.04" ]]; then
    echo "Setting up ROS $ROS_VERSION for Ubuntu $UBUNTU_VERSION..."
    
    # Check if ROS 2 Humble is already installed
    if [ -f "/opt/ros/humble/setup.bash" ]; then
        # Source it to check if ros2 command works
        source /opt/ros/humble/setup.bash
        if command -v ros2 &> /dev/null; then
            echo "[INFO] ROS 2 Humble is already installed:"
            echo "Location: $(which ros2)"
            echo "Setup file: /opt/ros/humble/setup.bash"
            echo "Skipping installation..."
            exit 0
        fi
    fi
    
    # Set locale
    echo "Setting up locale..."
    $SUDO apt update && $SUDO apt install locales -y
    $SUDO locale-gen en_US en_US.UTF-8
    $SUDO update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    export LANG=en_US.UTF-8
    
    # Setup Sources
    echo "Setting up ROS 2 apt repository..."
    $SUDO apt install software-properties-common -y
    $SUDO add-apt-repository universe -y
    
    $SUDO apt update && $SUDO apt install curl -y
    export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
    curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
    $SUDO dpkg -i /tmp/ros2-apt-source.deb
    
    # Install ROS 2 packages
    echo "Updating apt repository caches..."
    $SUDO apt update
    
    echo "Installing ROS 2 Humble Desktop..."
    $SUDO apt install ros-humble-desktop -y
    
    echo "Installing development tools..."
    $SUDO apt install ros-dev-tools -y
    
    # Environment setup
    echo "Setting up environment..."
    echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
    source /opt/ros/humble/setup.bash
    
    echo "ROS 2 Humble installation complete!"
    echo "To use ROS 2, run: source /opt/ros/humble/setup.bash"
    echo "Or open a new terminal (already added to ~/.bashrc)"
    
    # Test installation
    echo ""
    echo "Testing ROS 2 installation..."
    if command -v ros2 &> /dev/null; then
        echo "[OK] ros2 command found"
        echo "Location: $(which ros2)"
        
        # Check if key packages are installed
        if dpkg -l | grep -q ros-humble-desktop; then
            echo "[OK] ros-humble-desktop package installed"
        fi
        
        if dpkg -l | grep -q ros-dev-tools; then
            echo "[OK] ros-dev-tools package installed"
        fi
        
        echo ""
        echo "Installation verified successfully!"
        echo "You can test with: ros2 run demo_nodes_cpp talker"
    else
        echo "[WARNING] ros2 command not found. You may need to source the setup file:"
        echo "  source /opt/ros/humble/setup.bash"
    fi
    
elif [[ "$UBUNTU_VERSION" == "20.04" ]]; then
    if [[ "$1" == "--noetic" ]]; then
        ROS_VERSION="noetic"
        echo "Setting up ROS $ROS_VERSION for Ubuntu $UBUNTU_VERSION..."
        # Add commands to set up ROS Noetic
    else
        echo "Unsupported option. Use --noetic to set up ROS."
        exit 1
    fi
else
    echo "Unsupported Ubuntu version: $UBUNTU_VERSION"
    exit 1
fi