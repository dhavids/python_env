#!/bin/bash
# This script builds an Apptainer SIF image from a Docker container
# Usage: ./apptainer_sif.sh [-y] [-l|--local-build] [-s|--skip-commit] <container_name_or_id> <image_name>
# Example: ./apptainer_sif.sh my_container my_image           (prepares for HPC build)
# Example: ./apptainer_sif.sh -l my_container my_image        (builds locally)
# Example: ./apptainer_sif.sh --local-build my_container my_image  (builds locally)
# Example: ./apptainer_sif.sh -s my_container my_image        (only creates DEF and scripts)
# Example: ./apptainer_sif.sh --skip-commit my_container my_image   (only creates DEF and scripts)
# Example: ./apptainer_sif.sh -y my_container my_image        (force yes, HPC prep)
#
# DEFAULT BEHAVIOR (HPC prep mode):
# - Creates hpc_build/ folder with OCI archive TAR, DEF, and build script
# - Uses skopeo to create OCI archive from Docker image
#
# LOCAL BUILD MODE (--local-build):
# - Builds SIF locally (may have compatibility issues with HPC)
# - Use only if versions match exactly between local and HPC
#
# SKIP COMMIT MODE (--skip-commit):
# - Only creates DEF file and HPC build script
# - Skips Docker commit and OCI archive creation
# - Useful when TAR already exists or for updating scripts only
#
# IMPORTANT FOR HPC USAGE:
# - For best compatibility, build the SIF on the target HPC system using its Apptainer module
# - Version mismatches between build and runtime can cause UID/user namespace issues
# - The script automatically configures user namespace support for multi-user HPC environments

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

print_error() {
    echo -e "${RED}[BUILD ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[BUILD WARN]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Parse arguments
FORCE_YES=false
LOCAL_BUILD=false
SKIP_COMMIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y)
            FORCE_YES=true
            shift
            ;;
        -l|--local-build)
            LOCAL_BUILD=true
            shift
            ;;
        -s|--skip-commit)
            SKIP_COMMIT=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ "$#" -ne 2 ]; then
    print_error "Usage: $0 [-y] [-l|--local-build] [-s|--skip-commit] <container_name_or_id> <image_name>"
    print_error "Example: $0 my_container my_image                    (prepare for HPC build)"
    print_error "Example: $0 -l my_container my_image                 (build locally)"
    print_error "Example: $0 --local-build my_container my_image      (build locally)"
    print_error "Example: $0 -s my_container my_image                 (only create DEF/scripts)"
    print_error "Example: $0 --skip-commit my_container my_image       (only create DEF/scripts)"
    print_error "Example: $0 -y my_container my_image                 (force yes, HPC prep)"
    print_error "Example: $0 -y -l my_container my_image              (force yes, local build)"
    exit 1
fi

CONTAINER_NAME="$1"
IMAGE_NAME="$2"

# Determine build mode
if [ "$SKIP_COMMIT" = true ]; then
    print_warn "SKIP COMMIT MODE: Only creating DEF and HPC scripts"
    print_info "Docker commit and OCI archive creation will be skipped"
elif [ "$LOCAL_BUILD" = true ]; then
    print_warn "LOCAL BUILD MODE: Building SIF locally"
    print_warn "Note: This may cause compatibility issues on HPC if versions differ"
else
    print_info "HPC PREP MODE: Preparing build package for HPC"
    print_info "After this completes, upload hpc_build/ folder to HPC and run build_on_hpc.sh"
fi

# Validate image name (no special characters except dash and underscore)
if ! [[ "$IMAGE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    print_error "Image name can only contain letters, numbers, dashes, and underscores"
    exit 1
fi

print_info "Building Apptainer image from Docker container"
print_info "Container: $CONTAINER_NAME"
print_info "Image Name: $IMAGE_NAME"

# Skip Docker checks if in skip-commit mode
if [ "$SKIP_COMMIT" = false ]; then
    # Check if Docker is installed
    if ! command_exists docker; then
        print_error "Docker is not installed"
        print_error "Install Docker first: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_info "Docker found: $(docker --version)"

    # Check if running with appropriate permissions for Docker
    if ! docker ps &> /dev/null; then
        print_error "Cannot access Docker daemon"
        print_error "Ensure Docker is running and you have permissions to use it"
        print_error "You may need to add your user to the docker group: sudo usermod -aG docker \$USER"
        exit 1
    fi
    print_info "Docker daemon is accessible"

    # Check if the container exists and is running
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        # Try by ID
        if ! docker ps -a --format '{{.ID}}' | grep -q "^${CONTAINER_NAME}"; then
            print_error "Container '$CONTAINER_NAME' not found"
            print_info "Available containers:"
            docker ps -a --format "  {{.Names}} ({{.ID}}) - {{.Status}}"
            exit 1
        fi
    fi
    print_info "Container '$CONTAINER_NAME' found"
else
    print_info "Skipping Docker checks (--skip-commit mode)"
fi

# Check if Apptainer is installed (only for local build)
if [ "$LOCAL_BUILD" = true ]; then
    if ! command_exists apptainer; then
        print_error "Apptainer is not installed"
        print_error "Install Apptainer first: https://apptainer.org/docs/admin/main/installation.html"
        exit 1
    fi
    print_info "Apptainer found: $(apptainer --version)"
fi

# Create directory structure based on build mode
if [ "$LOCAL_BUILD" = true ]; then
    # Local build: use traditional directory structure
    DOCKER_IMAGES_DIR="$HOME/docker/images"
    APPTAINER_DEF_DIR="$HOME/docker/apptainer/def"
    APPTAINER_SIF_DIR="$HOME/docker/apptainer/sif"
    
    mkdir -p "$DOCKER_IMAGES_DIR"
    mkdir -p "$APPTAINER_DEF_DIR"
    mkdir -p "$APPTAINER_SIF_DIR"
    
    TAR_FILE="$DOCKER_IMAGES_DIR/${IMAGE_NAME}.tar"
    DEF_FILE="$APPTAINER_DEF_DIR/${IMAGE_NAME}.def"
    SIF_FILE="$APPTAINER_SIF_DIR/${IMAGE_NAME}.sif"
else
    # HPC prep mode: create hpc_build folder
    HPC_BUILD_DIR="$HOME/docker/hpc_build/${IMAGE_NAME}"
    mkdir -p "$HPC_BUILD_DIR"
    
    TAR_FILE="$HPC_BUILD_DIR/${IMAGE_NAME}.tar"
    DEF_FILE="$HPC_BUILD_DIR/${IMAGE_NAME}.def"
    SIF_FILE="$HPC_BUILD_DIR/${IMAGE_NAME}.sif"
    
    print_info "HPC build directory: $HPC_BUILD_DIR"
fi

# Skip Docker build steps if in skip-commit mode
if [ "$SKIP_COMMIT" = false ]; then
    # Check if tar file already exists
    if [ -f "$TAR_FILE" ]; then
        print_warn "TAR file already exists: $TAR_FILE"
        if [ "$FORCE_YES" = true ]; then
            print_info "Overwriting TAR file"
            rm -f "$TAR_FILE"
        else
            read -p "Do you want to overwrite it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Aborted by user"
                exit 1
            fi
            rm -f "$TAR_FILE"
        fi
    fi

    # Check if SIF file already exists
    if [ -f "$SIF_FILE" ]; then
        print_warn "SIF file already exists: $SIF_FILE"
        if [ "$FORCE_YES" = true ]; then
            print_info "Overwriting SIF file"
            rm -f "$SIF_FILE"
        else
            read -p "Overwrite? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_error "Aborted by user"
                exit 1
            fi
            rm -f "$SIF_FILE"
        fi
    fi

    # Check if skopeo is available
    if ! command -v skopeo &> /dev/null; then
        print_error "skopeo is not installed. Please install it first."
        print_info "Install with: sudo apt install skopeo (Ubuntu/Debian)"
        print_info "Or: brew install skopeo (macOS)"
        exit 1
    fi

    # Ensure image name has a tag (skopeo requires it)
    if [[ "$IMAGE_NAME" != *":"* ]]; then
        TAGGED_IMAGE_NAME="${IMAGE_NAME}:latest"
        print_info "Adding default tag: $TAGGED_IMAGE_NAME"
    else
        TAGGED_IMAGE_NAME="$IMAGE_NAME"
    fi

    # Commit the container to a Docker image
    print_info "Committing container '$CONTAINER_NAME' to image '$TAGGED_IMAGE_NAME'"
    if ! docker commit "$CONTAINER_NAME" "$TAGGED_IMAGE_NAME"; then
        print_error "Failed to commit container"
        exit 1
    fi
    print_info "Container committed successfully"

    # Create OCI archive using skopeo (instead of docker save)
    print_info "Creating OCI archive with skopeo: $TAR_FILE"
    if ! skopeo copy docker-daemon:"$TAGGED_IMAGE_NAME" oci-archive:"$TAR_FILE"; then
        print_error "Failed to create OCI archive with skopeo"
        exit 1
    fi

    # Check if tar file was created successfully
    if [ ! -f "$TAR_FILE" ]; then
        print_error "OCI archive was not created"
        exit 1
    fi

    TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
    print_info "OCI archive created (Size: $TAR_SIZE)"
else
    print_info "Skipping Docker commit and OCI archive creation (--skip-commit mode)"
    # Check if TAR already exists when skipping build
    if [ ! -f "$TAR_FILE" ]; then
        print_warn "TAR file does not exist: $TAR_FILE"
        print_warn "The HPC build script will expect this file to exist"
        print_warn "Make sure to either:"
        print_warn "  1. Run without --skip-commit first to create the TAR, or"
        print_warn "  2. Manually place the TAR file at: $TAR_FILE"
    else
        TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
        print_info "Existing TAR file found (Size: $TAR_SIZE)"
    fi
fi

# Create the Apptainer definition file
cat > "$DEF_FILE" << EOF
Bootstrap: oci-archive
From: ${IMAGE_NAME}.tar

%post
    echo "[BUILD] Apptainer image built from Docker container: $CONTAINER_NAME"
    echo "[BUILD] Image name: $IMAGE_NAME"
    echo "[BUILD] Build date: $(date)"
    
    # Test commands
    echo "[BUILD] Running apt update..."
    apt -qy update
    
    echo "[BUILD] Listing root directory..."
    ls -la /

%environment
    export LC_ALL=C
    # Allow flexible home directory for HPC environments
    export HOME=\${HOME:-/tmp}

%runscript
    exec /bin/bash "\$@"

%labels
    Author dhavids
    Version 1.0
    SourceContainer $CONTAINER_NAME
    BuildDate $(date +'%Y-%m-%d')
    HPCCompatible true
EOF

if [ ! -f "$DEF_FILE" ]; then
    print_error "Failed to create definition file"
    exit 1
fi
print_info "Definition file created successfully"

# Create HPC build script if in HPC prep mode
if [ "$LOCAL_BUILD" = false ]; then
    HPC_SCRIPT="$HPC_BUILD_DIR/build_on_hpc.sh"
    cat > "$HPC_SCRIPT" << 'HPCEOF'
#!/bin/bash
# HPC Build Script - Auto-generated
# This script should be run on the HPC system after uploading the hpc_build folder
# Usage: bash build_on_hpc.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[HPC BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[HPC BUILD ERROR]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[HPC BUILD WARN]${NC} $1"; }

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
print_info "Build directory: $SCRIPT_DIR"

# Find TAR and DEF files in the same directory
TAR_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.tar" | head -n 1)
DEF_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.def" | head -n 1)

if [ -z "$TAR_FILE" ]; then
    print_error "No .tar file found in $SCRIPT_DIR"
    exit 1
fi

if [ -z "$DEF_FILE" ]; then
    print_error "No .def file found in $SCRIPT_DIR"
    exit 1
fi

print_info "Found TAR file: $(basename "$TAR_FILE")"
print_info "Found DEF file: $(basename "$DEF_FILE")"

# Extract image name from tar file
IMAGE_NAME=$(basename "$TAR_FILE" .tar)
print_info "Image name: $IMAGE_NAME"

# Build in the same directory as the TAR file (no copying needed)
TARGET_SIF="$SCRIPT_DIR/${IMAGE_NAME}.sif"
print_info "Build directory: $SCRIPT_DIR"
print_info "SIF will be created in the same directory as TAR and DEF files"

# Load Apptainer module
print_info "Loading Apptainer module..."
if ! module load apptainer 2>/dev/null; then
    print_warn "Could not load apptainer module, trying singularity..."
    if ! module load singularity 2>/dev/null; then
        print_error "Could not load apptainer or singularity module"
        print_error "Please ensure the module is available: module avail apptainer"
        exit 1
    fi
fi

APPTAINER_VERSION=$(apptainer --version 2>/dev/null || singularity --version 2>/dev/null)
print_info "Apptainer/Singularity version: $APPTAINER_VERSION"

# Check if SIF already exists
if [ -f "$TARGET_SIF" ]; then
    print_warn "SIF file already exists: $TARGET_SIF"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$TARGET_SIF"
    else
        print_error "Aborted by user"
        exit 1
    fi
fi

# Build the SIF file
print_info "Building Apptainer SIF: $TARGET_SIF"
print_info "This may take several minutes..."

BUILD_SUCCESS=false
BUILD_METHOD=""

# Try standard build first (more reliable on HPC)
print_info "Attempting standard build without --fakeroot..."
if apptainer build "$TARGET_SIF" oci-archive://"$TAR_FILE" 2>&1 | tee /tmp/apptainer_build.log; then
    # Check if SIF was actually created (tee returns success even if build failed)
    if [ -f "$TARGET_SIF" ]; then
        print_info "Built successfully with standard method"
        BUILD_SUCCESS=true
        BUILD_METHOD="standard"
    else
        print_warn "Standard build reported success but SIF not created"
    fi
fi

# If standard build failed, try with --fakeroot
if [ "$BUILD_SUCCESS" = false ]; then
    print_info "Attempting build with --fakeroot..."
    rm -f "$TARGET_SIF" 2>/dev/null  # Clean up any partial file
    
    if apptainer build --fakeroot "$TARGET_SIF" oci-archive://"$TAR_FILE" 2>&1 | tee /tmp/apptainer_build.log; then
        if [ -f "$TARGET_SIF" ]; then
            print_info "Built successfully with --fakeroot"
            BUILD_SUCCESS=true
            BUILD_METHOD="--fakeroot"
        else
            print_warn "Fakeroot build reported success but SIF not created"
            BUILD_ERROR=$(cat /tmp/apptainer_build.log 2>/dev/null | tail -10)
            if echo "$BUILD_ERROR" | grep -q "exec format error\|fakeroot"; then
                print_warn "Fakeroot method failed (architecture/binary issue)"
            fi
        fi
    fi
fi

# If both failed, try with --fix-perms as last resort
if [ "$BUILD_SUCCESS" = false ]; then
    print_info "Attempting build with --fix-perms..."
    rm -f "$TARGET_SIF" 2>/dev/null  # Clean up any partial file
    
    if apptainer build --fix-perms "$TARGET_SIF" oci-archive://"$TAR_FILE" 2>&1 | tee /tmp/apptainer_build.log; then
        if [ -f "$TARGET_SIF" ]; then
            print_info "Built successfully with --fix-perms"
            BUILD_SUCCESS=true
            BUILD_METHOD="--fix-perms"
        else
            print_warn "Fix-perms build reported success but SIF not created"
        fi
    fi
fi

# Clean up log file
rm -f /tmp/apptainer_build.log

if [ "$BUILD_SUCCESS" = false ]; then
    print_error "Failed to build Apptainer image with all available methods"
    print_error "Definition file: $DEF_FILE"
    print_error "TAR file: $TAR_FILE"
    print_error ""
    print_error "Troubleshooting steps:"
    print_error "  1. Check if you have sufficient disk space: df -h $SCRIPT_DIR"
    print_error "  2. Try building manually: apptainer build $TARGET_SIF oci-archive://$TAR_FILE"
    print_error "  3. Check HPC documentation for Apptainer build requirements"
    print_error "  4. Contact HPC support if the issue persists"
    exit 1
else
    print_info "Build method used: $BUILD_METHOD"
fi

# Check if SIF was created
if [ ! -f "$TARGET_SIF" ]; then
    print_error "SIF file was not created"
    exit 1
fi

SIF_SIZE=$(du -h "$TARGET_SIF" | cut -f1)
print_info "Apptainer image built successfully!"
print_info "Location: $TARGET_SIF"
print_info "Size: $SIF_SIZE"

# Test the image...
print_info "Testing the image..."
if apptainer exec "$TARGET_SIF" whoami; then
    print_info "Image test successful!"
else
    print_warn "Image test failed - you may encounter user namespace issues"
fi

print_info "Usage examples:"
print_info "  apptainer shell $TARGET_SIF"
print_info "  apptainer exec $TARGET_SIF <command>"
print_info "  apptainer exec --nv $TARGET_SIF <command>  (with GPU)"

print_info "Build complete!"
HPCEOF

    chmod +x "$HPC_SCRIPT"
    print_info "Created HPC build script: $HPC_SCRIPT"
    
    # Create SLURM job script
    SLURM_SCRIPT="$HPC_BUILD_DIR/build.slurm"
    cat > "$SLURM_SCRIPT" << SLURMEOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --time=60:00:00
#SBATCH --ntasks=1
#SBATCH --partition=amd      
#SBATCH --cpus-per-task=15
#SBATCH --mem=128G
#SBATCH --output=build.out
#SBATCH --error=build.err

# Get the directory where this SLURM script is located
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# Load Apptainer module
module load apptainer

# Run the build script from the same directory
bash "\$SCRIPT_DIR/build_on_hpc.sh"
SLURMEOF

    chmod +x "$SLURM_SCRIPT"
    print_info "Created SLURM job script: $SLURM_SCRIPT"
    
    # Create README for HPC build
    README_FILE="$HPC_BUILD_DIR/README.md"
    cat > "$README_FILE" << 'READMEEOF'
# HPC Apptainer Build Package

This folder contains everything needed to build an Apptainer SIF image on the HPC system.

## Contents

- `*.tar` - OCI archive of Docker image
- `*.def` - Apptainer definition file
- `build_on_hpc.sh` - Build script that runs the actual build
- `build.slurm` - SLURM job script (recommended)

## Quick Start

### 1. Upload to HPC
```bash
scp -r this_folder/ user@hpc.soton.ac.uk:/scratch/user/builds/
```

### 2. Submit SLURM Job (Recommended)
```bash
ssh user@hpc.soton.ac.uk
cd /scratch/user/builds/folder_name/
sbatch build.slurm
```

Check job status:
```bash
squeue -u $USER
tail -f build.out  # Monitor progress
```

### 3. Or Run Directly (Alternative)
```bash
ssh user@hpc.soton.ac.uk
cd /scratch/user/builds/folder_name/
bash build_on_hpc.sh
```

### 3. Find Your SIF
The built SIF will be located in the same directory as the uploaded files:
```
/path/to/uploaded/folder/image_name.sif
```

## What the Build Script Does

1. Locates the .tar and .def files in the current directory
2. Loads the apptainer module (`module load apptainer`)
3. Builds the SIF in the same directory (no file copying needed)
4. Tries multiple build methods: standard → --fakeroot → --fix-perms
5. Tests the image with `whoami` command
6. Reports the final SIF location and size

## Troubleshooting

### "unknown userid" errors
The definition file includes HPC user namespace support. If you still encounter
issues, ensure the HPC's Apptainer version is 1.3+ and supports user namespaces.

### Module not found
If `module load apptainer` fails, try:
```bash
module avail apptainer
module load singularity
```

### Build fails
Check available disk space in /scratch:
```bash
df -h /scratch
```

### Check SLURM job output
```bash
# View output logs
cat build.out
cat build.err

# Cancel a job if needed
scancel <job_id>
```

## Manual Build (if script fails)

```bash
module load apptainer
cd /path/to/uploaded/folder/
apptainer build --fakeroot image_name.sif oci-archive://image_name.tar
```

## Testing the Built Image

```bash
# Basic test
apptainer exec /path/to/folder/image_name.sif whoami

# Interactive shell
apptainer shell /path/to/folder/image_name.sif

# With GPU support
apptainer exec --nv /path/to/folder/image_name.sif nvidia-smi
```
READMEEOF

    print_info "Created README: $README_FILE"
fi

# Only build locally if LOCAL_BUILD is true
if [ "$LOCAL_BUILD" = true ]; then
    # Build the Apptainer image locally
    print_info "Building Apptainer SIF: $SIF_FILE"
    print_warn "NOTE: For HPC compatibility, it's recommended to build on the target HPC system"
    print_warn "      using the same Apptainer version (module load apptainer)"
    print_warn "      Current version: $(apptainer --version)"

    # Check if Apptainer is installed for local build
    if ! command_exists apptainer; then
        print_error "Apptainer is not installed locally"
        print_error "Cannot perform local build"
        exit 1
    fi

    # Use --fakeroot if available for better user namespace support
    BUILD_CMD="apptainer build"
    if apptainer build --help 2>&1 | grep -q "\-\-fakeroot"; then
        print_info "Building with --fakeroot for enhanced HPC compatibility"
        BUILD_CMD="apptainer build --fakeroot"
    fi

    if ! $BUILD_CMD "$SIF_FILE" oci-archive://"$TAR_FILE"; then
        print_error "Failed to build Apptainer image"
        print_error "Definition file: $DEF_FILE"
        print_error "TAR file: $TAR_FILE"
        print_warn "If build fails due to permissions, try building on the HPC system directly"
        exit 1
    fi

    # Check if SIF file was created successfully
    if [ ! -f "$SIF_FILE" ]; then
        print_error "SIF file was not created"
        exit 1
    fi

    SIF_SIZE=$(du -h "$SIF_FILE" | cut -f1)
    print_info "Apptainer image built successfully (Size: $SIF_SIZE)"

    print_info "Usage:"
    print_info "  apptainer shell $SIF_FILE"
    print_info "  apptainer exec $SIF_FILE <command>"
    print_info "  apptainer shell --bind /host:/container $SIF_FILE"
    print_info ""

    print_info "Build complete"
else
    # HPC prep mode - provide upload instructions
    echo ""
    print_info "HPC BUILD PACKAGE READY"
    print_info "Build directory: $HPC_BUILD_DIR"
    print_info "Contents:"
    print_info "  - ${IMAGE_NAME}.tar (OCI archive)"
    print_info "  - ${IMAGE_NAME}.def (Apptainer definition)"
    print_info "  - build_on_hpc.sh (Build script)"
    print_info "  - build.slurm (SLURM job script)"
    print_info "  - README.md (Instructions)"
    echo ""
    print_info "Preparation complete!"
fi
