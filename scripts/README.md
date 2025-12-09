# Environment Setup Scripts

This document explains how to download and run setup scripts for different environment configurations.

## Available Configurations

### 1. ROS2 Humble with Gazebo

Download and run the setup script:

```bash
# Install wget if not available (for minimal Docker images)
apt update && apt install -y wget

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


### 2. ROS2 Humble with ARGoS

Download and run the setup script:

```bash
# Install wget if not available (for minimal Docker images)
apt update && apt install -y wget

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
