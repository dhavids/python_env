# This script will set up the ARGoS3 environment.
# ARGoS3 is a physics-based simulator for large-scale robot swarms.
# https://github.com/ilpincy/argos3

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
echo "ARGoS3 Setup Script"
echo "================================"

# Use MARL_DIR if set by parent script, otherwise use ~/marl
if [ -z "$MARL_DIR" ]; then
    MARL_DIR="$HOME/marl"
fi

# Installation directories
ARGOS3_DIR="$MARL_DIR/argos3"
ARGOS3_BUILD_DIR="$ARGOS3_DIR/build_simulator"
ARGOS3_EXAMPLES_DIR="$MARL_DIR/argos3-examples"
ARGOS3_EXAMPLES_BUILD_DIR="$ARGOS3_EXAMPLES_DIR/build"

echo "MARL workspace: $MARL_DIR"
echo ""

# Check if ARGoS3 is already installed
if command -v argos3 &> /dev/null; then
    echo "[INFO] ARGoS3 is already installed:"
    echo "Location: $(which argos3)"
    argos3 --version 2>/dev/null || echo "Version: $(argos3 -q all 2>&1 | head -1)"
    echo "Skipping installation..."
    exit 0
fi

# Install dependencies - rsync added for other scripts
echo "Installing ARGoS3 dependencies..."
$SUDO apt update
$SUDO apt install -y \
    cmake \
    libfreeimage-dev \
    libfreeimageplus-dev \
    qt5-qmake \
    qtbase5-dev \
    libqt5opengl5-dev \
    freeglut3-dev \
    libxi-dev \
    libxmu-dev \
    liblua5.3-dev \
    lua5.3 \
    doxygen \
    graphviz \
    libgraphviz-dev \
    asciidoc \
    rsync

echo "Dependencies installed successfully!"
echo ""

# Clone or update ARGoS3
if [ ! -d "$ARGOS3_DIR" ]; then
    echo "Cloning ARGoS3 repository..."
    cd "$MARL_DIR"
    git clone https://github.com/ilpincy/argos3.git argos3
else
    echo "ARGoS3 repository already exists. Pulling latest changes..."
    cd "$ARGOS3_DIR"
    git pull
fi

echo ""

# Build ARGoS3
echo "Building ARGoS3..."
mkdir -p "$ARGOS3_BUILD_DIR"
cd "$ARGOS3_BUILD_DIR"

cmake -DCMAKE_BUILD_TYPE=Release \
      -DARGOS_BUILD_FOR=simulator \
      -DARGOS_INSTALL_LDSOCONF=ON \
      -DARGOS_DOCUMENTATION=OFF \
      ../src

make -j$(nproc)

echo "ARGoS3 build complete!"
echo ""

# Install ARGoS3
echo "Installing ARGoS3..."
$SUDO make install

echo "ARGoS3 installed successfully!"
echo ""

# Fix common shared library errors
echo "Fixing shared library paths..."

# Add /usr/local/lib to ld.so.conf if not already present
if ! grep -q "^/usr/local/lib$" /etc/ld.so.conf.d/*.conf 2>/dev/null && \
   ! grep -q "^/usr/local/lib$" /etc/ld.so.conf 2>/dev/null; then
    echo "Adding /usr/local/lib to ld.so.conf..."
    echo "/usr/local/lib" | $SUDO tee /etc/ld.so.conf.d/argos3.conf
fi

# Run ldconfig to update shared library cache
$SUDO ldconfig

echo "Shared library paths configured!"
echo ""

# Fix Qt5 library issue for apptainer/singularity
echo "Fixing Qt5 library for apptainer compatibility..."
if [ -f /usr/lib/x86_64-linux-gnu/libQt5Core.so.5 ]; then
    # Backup the original file
    if [ ! -f /usr/lib/x86_64-linux-gnu/libQt5Core.so.5.backup ]; then
        $SUDO cp /usr/lib/x86_64-linux-gnu/libQt5Core.so.5 \
                /usr/lib/x86_64-linux-gnu/libQt5Core.so.5.backup
    fi
    
    # Strip the ABI tag
    $SUDO strip --remove-section=.note.ABI-tag /usr/lib/x86_64-linux-gnu/libQt5Core.so.5
    echo "Qt5 library fixed for apptainer!"
else
    echo "Warning: libQt5Core.so.5 not found, skipping apptainer fix"
fi

echo ""

# Clone or update ARGoS3 examples
if [ ! -d "$ARGOS3_EXAMPLES_DIR" ]; then
    echo "Cloning ARGoS3 examples repository..."
    cd "$MARL_DIR"
    git clone https://github.com/ilpincy/argos3-examples.git argos3-examples
else
    echo "ARGoS3 examples repository already exists. Pulling latest changes..."
    cd "$ARGOS3_EXAMPLES_DIR"
    git pull
fi

echo ""

# Build ARGoS3 examples
echo "Building ARGoS3 examples..."
mkdir -p "$ARGOS3_EXAMPLES_BUILD_DIR"
cd "$ARGOS3_EXAMPLES_BUILD_DIR"

cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)

echo "ARGoS3 examples built successfully!"
echo ""

# Test ARGoS3 installation
echo "================================"
echo "Testing ARGoS3 Installation"
echo "================================"

# Check if argos3 command is available
if command -v argos3 &> /dev/null; then
    echo "[OK] argos3 command found"
    argos3 --version
    echo ""
    
    # Query all plugins
    echo "Available ARGoS3 plugins:"
    argos3 -q all
    echo ""
    
    # Run a simple example
    echo "Running diffusion example (headless mode for 10 seconds)..."
    cd "$ARGOS3_EXAMPLES_DIR"
    
    if [ -f experiments/diffusion_1.argos ]; then
        # Set environment to prevent Qt from trying to use Wayland
        export QT_QPA_PLATFORM=offscreen
        
        # Run the example and capture exit code
        set +e
        timeout 10s argos3 -c experiments/diffusion_1.argos -n > /tmp/argos_test.log 2>&1
        ARGOS_EXIT_CODE=$?
        set -e
        
        # Check if argos3 ran (exit code 0 or 124 for timeout is acceptable)
        if [ $ARGOS_EXIT_CODE -eq 0 ] || [ $ARGOS_EXIT_CODE -eq 124 ]; then
            echo ""
            echo "[OK] Example ran successfully!"
            
            # Clean up examples folder after successful test
            echo ""
            echo "Cleaning up examples folder..."
            cd "$MARL_DIR"
            rm -rf "$ARGOS3_EXAMPLES_DIR"
            echo "[OK] Examples folder removed"
            
            echo ""
            echo "================================"
            echo "ARGoS3 Installation Complete!"
            echo "================================"
            echo ""
            echo "ARGoS3 is installed and working correctly."
            echo "You can query ARGoS3 plugins anytime with: argos3 -q all"
            echo ""
        else
            echo ""
            echo "[ERROR] Example failed to run (exit code: $ARGOS_EXIT_CODE)"
            echo "Last 20 lines of output:"
            tail -n 20 /tmp/argos_test.log
            echo "ARGoS3 may not be properly configured"
            exit 1
        fi
    else
        echo "[ERROR] Example configuration file not found"
        echo "ARGoS3 is installed, but examples may not be properly configured"
        exit 1
    fi
else
    echo "[ERROR] argos3 command not found"
    echo "Installation may have failed. Try running 'ldconfig' and check /usr/local/bin"
    exit 1
fi


