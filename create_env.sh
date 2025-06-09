#!/bin/bash
# filepath: /home/u20/argos/python_env/create_env.sh

set -e  # Exit on any error

# Get the directory where this script is located (python_env)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FOLDER="$(dirname "$SCRIPT_DIR")"
PARENT_FOLDER="$(dirname "$BASE_FOLDER")"

echo "Script directory: $SCRIPT_DIR"
echo "Base folder: $BASE_FOLDER"
echo "Parent folder: $PARENT_FOLDER"
echo

# Function to get Python version
get_python_version() {
    local python_cmd="$1"
    if command -v "$python_cmd" &> /dev/null; then
        local version=$("$python_cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        echo "$version"
    else
        echo ""
    fi
}

# Function to check if Python version is >= 3.8
is_python_valid() {
    local version="$1"
    if [[ -n "$version" ]]; then
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        if [[ "$major" -ge 3 && "$minor" -ge 8 ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to check if a package is installed
is_package_installed() {
    local package_name="$1"
    pip show "$package_name" &> /dev/null
    return $?
}

# Check if e-swarm environment exists in parent folder
E_SWARM_PATH="$PARENT_FOLDER/e-swarm"
SCRATCH_E_SWARM_PATH="/scratch/aoa1v22/envs/e-swarm"

if [[ -d "$E_SWARM_PATH" ]]; then
    echo "Found e-swarm environment at: $E_SWARM_PATH"
    VENV_PATH="$E_SWARM_PATH"
elif [[ -d "$SCRATCH_E_SWARM_PATH" ]]; then
    echo "Found e-swarm environment at: $SCRATCH_E_SWARM_PATH"
    VENV_PATH="$SCRATCH_E_SWARM_PATH"
else
    # Need to create environment
    echo "e-swarm environment not found. Creating new environment..."
    
    # Determine where to create the environment
    if [[ -d "/scratch" ]]; then
        mkdir -p "/scratch/aoa1v22/envs"
        VENV_PATH="/scratch/aoa1v22/envs/e-swarm"
        echo "Will create environment at: $VENV_PATH"
    else
        VENV_PATH="$PARENT_FOLDER/e-swarm"
        echo "Will create environment at: $VENV_PATH"
    fi
    
    # Find suitable Python version
    PYTHON_CMD=""
    PYTHON_VERSION=""
    
    # Try Python 3.8 first (default)
    for py_cmd in "python3.8" "python3.10" "python3.11" "python3.12" "python3" "python"; do
        version=$(get_python_version "$py_cmd")
        if is_python_valid "$version"; then
            PYTHON_CMD="$py_cmd"
            PYTHON_VERSION="$version"
            echo "Using Python $version ($py_cmd)"
            break
        fi
    done
    
    if [[ -z "$PYTHON_CMD" ]]; then
        echo "Error: No suitable Python version (>= 3.8) found!"
        exit 1
    fi
    
    # Create virtual environment
    echo "Creating virtual environment with $PYTHON_CMD..."
    "$PYTHON_CMD" -m venv "$VENV_PATH"
fi
echo

# Activate the environment
echo "Activating environment: $VENV_PATH"
source "$VENV_PATH/bin/activate"
echo

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip
echo

# Check if base folder has setup.py
SETUP_PY_PATH="$BASE_FOLDER/setup.py"
if [[ ! -f "$SETUP_PY_PATH" ]]; then
    echo "setup.py not found in base folder. Copying from python_env..."
    cp "$SCRIPT_DIR/setup.py" "$SETUP_PY_PATH"
fi
echo

# Install base folder in editable mode (check if already installed)
if is_package_installed "local"; then
    echo "Base folder package 'local' is already installed. Skipping..."
else
    echo "Installing base folder in editable mode..."
    cd "$BASE_FOLDER"
    pip install -e .
fi
echo

# Install mappo if it exists
MAPPO_PATH="$BASE_FOLDER/mappo"
if [[ -d "$MAPPO_PATH" ]]; then
    if is_package_installed "onpolicy"; then
        echo "Mappo package 'onpolicy' is already installed. Skipping..."
    else
        echo "Installing mappo in editable mode..."
        cd "$MAPPO_PATH"
        if [[ -f "setup.py" ]]; then
            pip install -e .
        else
            echo "Warning: mappo directory exists but no setup.py found"
        fi
    fi
    echo
fi

# Install requirements based on Python version
cd "$SCRIPT_DIR"
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python version in environment: $PYTHON_VERSION"

REQ_FILE=""
if [[ -f "requirements/e-swarm-python-$PYTHON_VERSION.txt" ]]; then
    REQ_FILE="requirements/e-swarm-python-$PYTHON_VERSION.txt"
elif [[ -f "requirements/e-swarm-python-3.8.txt" ]]; then
    REQ_FILE="requirements/e-swarm-python-3.8.txt"
    echo "Warning: Using Python 3.8 requirements for Python $PYTHON_VERSION"
else
    echo "Error: No suitable requirements file found!"
    exit 1
fi

echo "Installing requirements from: $REQ_FILE"
pip install -r "$REQ_FILE"
echo

echo "Environment setup complete!"
echo "Virtual environment path: $VENV_PATH"
echo "To activate manually: source $VENV_PATH/bin/activate"
echo

# Return to base folder
cd "$BASE_FOLDER"