# This script will download and set up the necessary repositories for the project.
# It will try to do so using git ssh and if it fails it will prompt you to get the GPG key
# All repositories will be cloned into ~/marl directory

#!/bin/bash
set -e

# Use MARL_DIR if set by parent script, otherwise use ~/marl
if [ -z "$MARL_DIR" ]; then
    MARL_DIR="$HOME/marl"
fi

# TODO: Handle mappo-gail and mappo_gail renaming issue
USERNAME="dhavids"
REPOS=(
    "argos_il"
    "configs"
    "docs"
    "mappo"
    "mappo-gail"
    "mpe"
    "python_env"
    "translator"
    "turtlebot3_il"
)

echo "================================"
echo "Repository Setup Script"
echo "================================"
echo "Cloning repositories into: $MARL_DIR"
echo ""

# Create repos directory
mkdir -p "$MARL_DIR"
cd "$MARL_DIR"

for REPO in "${REPOS[@]}"; do
    echo "Processing $REPO repository..."
    if [ -d "$REPO" ]; then
        echo "[INFO] $REPO already exists, checking for ros2 branch..."
        cd "$REPO"
        
        # Check if ros2 branch exists locally first
        if git show-ref --verify --quiet refs/heads/ros2; then
            # ros2 branch exists locally
            CURRENT_BRANCH=$(git branch --show-current)
            if [ "$CURRENT_BRANCH" != "ros2" ]; then
                echo "[INFO] Switching to local ros2 branch..."
                git checkout ros2
            fi
            echo "[INFO] Pulling updates for ros2 branch..."
            git pull origin ros2 || echo "[WARNING] Failed to pull updates for ros2 branch"
        else
            # ros2 doesn't exist locally, check remote
            echo "[INFO] Checking remote for ros2 branch..."
            if git ls-remote --heads origin ros2 | grep -q ros2; then
                echo "[INFO] ros2 branch found on remote, checking out..."
                git checkout -b ros2 origin/ros2
                git pull origin ros2 || echo "[WARNING] Failed to pull updates for ros2 branch"
            else
                echo "[INFO] ros2 branch not found, using current branch"
                git pull || echo "[WARNING] Failed to pull updates for $REPO"
            fi
        fi
        
        cd "$MARL_DIR"
    else
        echo "Cloning $REPO..."
        if ! git clone "git@github.com:$USERNAME/$REPO.git"; then
            echo ""
            echo "[ERROR] Failed to clone $REPO repository."
            echo "This could be due to:"
            echo "  - SSH connection issues (Connection reset by peer)"
            echo "  - Missing SSH key or incorrect permissions"
            echo ""
            echo "To set up your SSH key, follow these steps:"
            echo "1. Generate a new SSH key using 'ssh-keygen -t rsa -b 4096 -C \"your_email@example.com\"'"
            echo "2. Display the public key using 'cat ~/.ssh/id_rsa.pub' and copy it."
            echo "3. Add the SSH key to your GitHub account at: https://github.com/settings/keys"
            echo ""
            echo "For connection issues, try again in a few minutes."
            exit 1
        fi
        
        # After cloning, check if ros2 branch exists locally
        cd "$REPO"
        if git show-ref --verify --quiet refs/heads/ros2; then
            echo "[INFO] ros2 branch exists locally, checking out..."
            git checkout ros2
        else
            # Check remote for ros2 branch
            echo "[INFO] Checking remote for ros2 branch..."
            if git ls-remote --heads origin ros2 | grep -q ros2; then
                echo "[INFO] ros2 branch found on remote, checking out..."
                git checkout -b ros2 origin/ros2
            else
                echo "[INFO] ros2 branch not found, staying on default branch"
            fi
        fi
        cd "$MARL_DIR"
        
        # Rename mappo-gail to mappo_gail for consistency
        if [ "$REPO" = "mappo-gail" ]; then            
            # If the new folder already exists, remove the old one to avoid duplicates
            if [ -d "$MARL_DIR/mappo_gail" ]; then
                echo "[INFO] mappo_gail already exists, removing mappo-gail..."
                rm -rf "$MARL_DIR/mappo-gail"
            else
                echo "[INFO] Renaming mappo-gail to mappo_gail..."
                mv "$MARL_DIR/mappo-gail" "$MARL_DIR/mappo_gail"
            fi
        fi

        # For turtlebot3_il, install dependencies
        if [ "$REPO" = "turtlebot3_il" ]; then
            echo ""
            echo "Installing TurtleBot3 IL dependencies..."
            
            # Check if README.md exists
            README_PATH="$MARL_DIR/turtlebot3_il/README.md"
            if [ ! -f "$README_PATH" ]; then
                echo "[WARNING] README.md not found at $README_PATH, skipping dependency installation"
            else
                # Create dev_ws/src directory if it doesn't exist
                mkdir -p "$MARL_DIR/turtlebot3_il/dev_ws/src"
                cd "$MARL_DIR/turtlebot3_il/dev_ws/src"
                
                # Extract git clone commands from README.md
                # Look for lines containing 'git clone' inside code blocks
                GIT_COMMANDS=$(grep -o '`git clone[^`]*`' "$README_PATH" | sed 's/`//g')
                
                if [ -z "$GIT_COMMANDS" ]; then
                    echo "[INFO] No git clone commands found in README.md"
                else
                    # Process each git clone command
                    while IFS= read -r CMD; do
                        if [ -n "$CMD" ]; then
                            # Extract repository name from the URL
                            REPO_NAME=$(echo "$CMD" | grep -oP '([^/]+)\.git' | sed 's/\.git//')
                            
                            if [ -d "$REPO_NAME" ]; then
                                echo "[INFO] $REPO_NAME already exists"
                            else
                                echo "Executing: $CMD"
                                eval "$CMD" || echo "[WARNING] Failed to execute: $CMD"
                            fi
                        fi
                    done <<< "$GIT_COMMANDS"
                fi
                
                cd "$MARL_DIR"
                echo "[OK] TurtleBot3 IL dependencies processed"
            fi
        fi
    fi
done

# After cloning all repositories, run the setup script in the python-env repository
echo ""
echo "Running setup script in python_env repository..."
cd "$MARL_DIR/python_env"
bash create_env.sh

echo ""
echo "[OK] All repositories cloned successfully!"
echo "Repositories location: $MARL_DIR"
