#!/bin/bash
# This script sets up ROS2 Humble and Gazebo by cloning the python_env repository
# and using its setup scripts
# Usage: bash setup_u22_gazebo.sh

set -e

# Detect if we need sudo (not in Docker or running as root)
if [ "$EUID" -eq 0 ] || ! command -v sudo &> /dev/null; then
    SUDO=""
    echo "[INFO] Running without sudo (Docker or root user)"
else
    SUDO="sudo"
fi

WORKSPACE_DIR="$(pwd)"
PYTHON_ENV_REPO="https://github.com/dhavids/python_env.git"
PYTHON_ENV_DIR="$WORKSPACE_DIR/python_env"

echo "================================"
echo "ROS2 + Gazebo Setup"
echo "Ubuntu 22.04"
echo "================================"
echo "Working directory: $WORKSPACE_DIR"
echo ""

# Update system packages
echo "Updating package lists..."
$SUDO apt update

# Install essential build tools and libraries
echo "Installing essential build tools and libraries..."
$SUDO apt install -y build-essential cmake git wget curl unzip pkg-config \
    libssl-dev libffi-dev python3-dev python3-pip python3-venv

# Clone or update python_env repository
echo ""
echo "================================"
echo "Setting up python_env repository"
echo "================================"

if [ -d "$PYTHON_ENV_DIR/.git" ]; then
    echo "[INFO] python_env repository exists, updating..."
    cd "$PYTHON_ENV_DIR"
    git fetch origin
    git pull origin main || echo "[WARNING] Failed to pull updates"
    cd "$WORKSPACE_DIR"
elif [ -d "$PYTHON_ENV_DIR" ]; then
    echo "[WARNING] python_env directory exists but is not a git repo, removing..."
    rm -rf "$PYTHON_ENV_DIR"
    echo "Cloning python_env repository..."
    git clone "$PYTHON_ENV_REPO" "$PYTHON_ENV_DIR"
else
    echo "Cloning python_env repository..."
    git clone "$PYTHON_ENV_REPO" "$PYTHON_ENV_DIR"
fi

echo "[OK] python_env repository ready"

# Verify required setup scripts exist
echo ""
echo "Verifying required setup scripts..."

SETUP_DIR="$PYTHON_ENV_DIR/scripts/setup"
REQUIRED_SCRIPTS=(
    "$SETUP_DIR/ros.sh"
    "$SETUP_DIR/gazebo.sh"
)

MISSING_SCRIPTS=()

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        MISSING_SCRIPTS+=("$script")
    fi
done

if [ ${#MISSING_SCRIPTS[@]} -gt 0 ]; then
    echo ""
    echo "[ERROR] Missing required setup scripts:"
    for script in "${MISSING_SCRIPTS[@]}"; do
        echo "  - $script"
    done
    echo ""
    echo "Please check the python_env repository structure."
    exit 1
fi

echo "[OK] All required scripts found"

# Install ROS2 Humble
echo ""
echo "Setting up ROS 2 Humble..."
bash "$SETUP_DIR/ros.sh"

# Install Gazebo
echo ""
echo "Setting up Gazebo..."
bash "$SETUP_DIR/gazebo.sh"

echo ""
echo "============================================================"
echo "ROS2 + Gazebo Setup Complete!"
echo "============================================================"
echo ""
echo "ROS2 Humble and Gazebo have been installed."
echo ""
echo "To use ROS2, source the setup file:"
echo "  source /opt/ros/humble/setup.bash"
echo ""
echo "To test Gazebo:"
echo "  gazebo --version"
echo "============================================================"