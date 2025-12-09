# This script will set up Gazebo and dependent ROS 2 packages for TurtleBot3.
# Based on: https://emanual.robotis.com/docs/en/platform/turtlebot3/quick-start/
# This script installs Gazebo, Cartographer, and Navigation2 packages.
# TurtleBot3 dependencies are handled by repo.sh

#!/bin/bash
set -e

# Detect if we need sudo (not in Docker or running as root)
if [ "$EUID" -eq 0 ] || ! command -v sudo &> /dev/null; then
    SUDO=""
    echo "[INFO] Running without sudo (Docker or root user)"
else
    SUDO="sudo"
fi

echo "================================"
echo "Gazebo & ROS 2 Dependencies Setup"
echo "================================"
echo ""

# Check if ROS 2 Humble is installed
if [ ! -f "/opt/ros/humble/setup.bash" ]; then
    echo "[ERROR] ROS 2 Humble is not installed."
    echo "Please run the ros.sh setup script first."
    exit 1
fi

echo "[INFO] ROS 2 Humble found at /opt/ros/humble"
source /opt/ros/humble/setup.bash
echo ""

# Install Gazebo packages
echo "Installing Gazebo packages for ROS 2 Humble..."
$SUDO apt update
$SUDO apt install -y ros-humble-gazebo-*

echo "[OK] Gazebo packages installed"
echo ""

# Install Cartographer
echo "Installing Cartographer packages..."
$SUDO apt install -y ros-humble-cartographer ros-humble-cartographer-ros

echo "[OK] Cartographer installed"
echo ""

# Install Navigation2
echo "Installing Navigation2 packages..."
$SUDO apt install -y ros-humble-navigation2 ros-humble-nav2-bringup

echo "[OK] Navigation2 installed"
echo ""

# Install colcon build tools if not already installed
if ! command -v colcon &> /dev/null; then
    echo "Installing colcon build tools..."
    $SUDO apt install -y python3-colcon-common-extensions
    echo "[OK] Colcon installed"
else
    echo "[INFO] Colcon already installed"
fi
echo ""

# Setup Gazebo environment in bashrc if not already present
BASHRC="$HOME/.bashrc"
GAZEBO_SETUP="source /usr/share/gazebo/setup.sh"

if ! grep -q "$GAZEBO_SETUP" "$BASHRC"; then
    echo "Adding Gazebo setup to ~/.bashrc..."
    echo "" >> "$BASHRC"
    echo "# Gazebo setup" >> "$BASHRC"
    echo "$GAZEBO_SETUP" >> "$BASHRC"
    echo "[OK] Gazebo setup added to ~/.bashrc"
else
    echo "[INFO] Gazebo setup already in ~/.bashrc"
fi
echo ""

# Source Gazebo setup for current session
if [ -f /usr/share/gazebo/setup.sh ]; then
    source /usr/share/gazebo/setup.sh
    echo "[OK] Gazebo environment sourced"
else
    echo "[WARNING] /usr/share/gazebo/setup.sh not found"
fi
echo ""

echo "================================"
echo "✓ Gazebo Setup Complete!"
echo "================================"
echo ""
echo "Installed packages:"
echo "  - Gazebo (ros-humble-gazebo-*)"
echo "  - Cartographer (SLAM)"
echo "  - Navigation2 (Nav2)"
echo "  - Colcon build tools"
echo ""
echo "Note: TurtleBot3 packages will be installed by repo.sh"
echo ""
echo "To verify installation, run:"
echo "  ros2 pkg list | grep gazebo"
echo "  ros2 pkg list | grep cartographer"
echo "  ros2 pkg list | grep nav2"
echo ""
