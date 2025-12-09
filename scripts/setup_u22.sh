# This script will set up the environment for Ubuntu 22.04.
# All installations will be done in ~/marl directory.
# This script can be run from anywhere and will set up everything correctly.

#!/bin/bash
set -e

# Detect if we need sudo (not in Docker or running as root)
if [ "$EUID" -eq 0 ] || ! command -v sudo &> /dev/null; then
    SUDO=""
    echo "[INFO] Running without sudo (Docker or root user)"
else
    SUDO="sudo"
fi

# Create and set up the MARL workspace
MARL_DIR="$HOME/marl"
UTIL_DIR="$MARL_DIR/util"
SETUP_DIR="$UTIL_DIR/scripts/setup"

echo "================================"
echo "Ubuntu 22.04 Setup Script"
echo "================================"
echo "Setting up MARL workspace at: $MARL_DIR"
echo ""

# Create marl directory if it doesn't exist
mkdir -p "$MARL_DIR"

# Update system packages (no upgrade to save time)
echo "Updating package lists..."
$SUDO apt update

# Install essential build tools and libraries
echo "Installing essential build tools and libraries..."
$SUDO apt install -y build-essential cmake git wget curl unzip pkg-config \
    libssl-dev libffi-dev python3-dev python3-pip python3-venv

echo ""
echo "================================"
echo "Setting up util repository"
echo "================================"

# Function to clone util repository with error handling
clone_util_repo() {
    echo "Cloning util repository..."
    cd "$MARL_DIR"
    if ! git clone git@github.com:dhavids/util.git; then
        echo ""
        echo "[ERROR] Failed to clone util repository."
        echo ""
        echo "To set up your SSH key, follow these steps:"
        echo "1. Generate a new SSH key:"
        echo "   ssh-keygen -t rsa -b 4096 -C \"your_email@example.com\""
        echo ""
        echo "2. Display your public key:"
        echo "   cat ~/.ssh/id_rsa.pub"
        echo ""
        echo "3. Copy the output and add it to your GitHub account:"
        echo "   - Go to: https://github.com/settings/keys"
        echo "   - Click 'New SSH key'"
        echo "   - Paste your public key"
        echo ""
        echo "4. Test your SSH connection:"
        echo "   ssh -T git@github.com"
        echo ""
        echo "After setting up SSH, run this script again."
        exit 1
    fi
}

# Check if util exists and is a git repo
if [ -d "$UTIL_DIR/.git" ]; then
    echo "[INFO] Util repository exists, fetching latest changes..."
    cd "$UTIL_DIR"
    git fetch origin
    git pull origin main || echo "[WARNING] Failed to pull util updates"
    cd "$MARL_DIR"
elif [ -d "$UTIL_DIR" ]; then
    echo "[INFO] Util directory exists but is not a git repo, removing..."
    rm -rf "$UTIL_DIR"
    clone_util_repo
else
    clone_util_repo
fi
echo "[OK] Util repository ready"

# Verify all required setup scripts exist
echo ""
echo "Verifying required setup scripts..."

REQUIRED_SCRIPTS=(
    "$SETUP_DIR/ros.sh"
    "$SETUP_DIR/argos3.sh"
    "$SETUP_DIR/gazebo.sh"
    "$SETUP_DIR/repo.sh"
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
    echo "Please ensure the util repository is properly cloned at: $UTIL_DIR"
    exit 1
fi

echo "[OK] All required scripts found"

# Set SCRIPT_DIR to the setup directory
SCRIPT_DIR="$SETUP_DIR"

# Export MARL_DIR for use by other scripts
export MARL_DIR

cd "$MARL_DIR"

# Install ros2 Humble
echo ""
echo "Setting up ROS 2 Humble..."
bash "$SCRIPT_DIR/ros.sh"

# Install Argos3
echo ""
echo "Setting up Argos3..."
bash "$SCRIPT_DIR/argos3.sh"

# Install Gazebo and dependencies
echo ""
echo "Setting up Gazebo..."
bash "$SCRIPT_DIR/gazebo.sh"

# Set up project repositories
echo ""
echo "Setting up project repositories..."
cd "$MARL_DIR"
bash "$SCRIPT_DIR/repo.sh"

# Update bash with auto-completion scripts
echo ""
echo "Setting up bash auto-completion..."
AUTOCOMP_SCRIPT="$UTIL_DIR/auto_comp/update_bash.sh"
if [ -f "$AUTOCOMP_SCRIPT" ]; then
    bash "$AUTOCOMP_SCRIPT" "$UTIL_DIR/auto_comp"
    echo "[OK] Bash auto-completion configured"
else
    echo "[WARNING] Auto-completion script not found at: $AUTOCOMP_SCRIPT"
fi

# Change to base directory for running the command
cd "$MARL_DIR"

# Create id.txt file with appropriate environment identifier
if [ -z "$SUDO" ]; then
    echo "docker" > id.txt
else
    echo "virtual machine" > id.txt
fi

echo ""
echo "============================================================"
echo "✓ Setup Complete!"
echo "============================================================"
echo ""
echo "Your MARL workspace is ready at: $MARL_DIR"
echo ""
echo "Next Steps:"
echo "------------"
echo ""
echo "1. Source your new bash configuration:"
echo "   source ~/.bashrc"
echo ""
echo "2. Build the ROS2 workspace:"
echo "   cd ~/marl/argos_il/dev_ws"
echo "   colcon build --symlink-install"
echo ""
echo "3. Test the workflow with the experts command:"
echo "   experts --scenario grid --simple_obs --max_trajs 5"
echo "============================================================"
echo ""