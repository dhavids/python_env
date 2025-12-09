# Environment Setup Scripts

This document explains how to download and run setup scripts for different environment configurations.

## Available Configurations

### 1. ROS2 Humble with Gazebo

Download and run the setup script:

```bash
# Download the script
wget https://raw.githubusercontent.com/dhavids/python_env/main/scripts/setup_u22_gazebo.sh

# Make it executable
chmod +x setup_u22_gazebo.sh

# Run the script
bash setup_u22_gazebo.sh
```

**What this installs:**
- ROS2 Humble
- Gazebo simulator

**After installation:**
```bash
# Source ROS2
source /opt/ros/humble/setup.bash

# Test Gazebo
gazebo --version
```

### 2. ROS2 Humble with ARGoS

Download and run the setup script:

```bash
# Download the script
wget https://raw.githubusercontent.com/dhavids/python_env/main/scripts/setup_u22_argos.sh

# Make it executable
chmod +x setup_u22_argos.sh

# Run the script
bash setup_u22_argos.sh
```

**What this installs:**
- ROS2 Humble
- ARGoS3 simulator

**After installation:**
```bash
# Source ROS2
source /opt/ros/humble/setup.bash

# Test ARGoS
argos3 --version
```

---

## Notes

- All scripts automatically clone the `python_env` repository to access the required setup scripts
- Scripts detect if running in Docker (no sudo) or on a VM/bare metal (with sudo)
- Essential build tools and dependencies are installed automatically
- If `python_env` already exists, it will be updated from the repository

## Requirements

- Ubuntu 22.04
- Internet connection
- Sudo privileges (unless running in Docker)

## Troubleshooting

If a script fails:

1. **Check internet connection** - Scripts need to download packages and clone repositories
2. **Ensure sufficient disk space** - ROS2 and simulators require several GB
3. **Review error messages** - Scripts will indicate which component failed
4. **Re-run the script** - Many transient errors can be resolved by running again

## Manual Installation

If you prefer to install components individually, you can use the component scripts directly from the `python_env` repository:

```bash
# Clone the repository
git clone https://github.com/dhavids/python_env.git
cd python_env/scripts/setup

# Run individual setup scripts
bash ros.sh              # Install ROS2 Humble
bash gazebo.sh           # Install Gazebo
bash argos3.sh           # Install ARGoS3
bash turtlebot3.sh       # Install TurtleBot3
```