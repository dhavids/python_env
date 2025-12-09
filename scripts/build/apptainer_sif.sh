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
elif [ "$LOCAL_BUILD" = true ]; then
    print_warn "LOCAL BUILD MODE: Building SIF locally (may cause compatibility issues on HPC)"
else
    print_info "HPC PREP MODE: Preparing build package for HPC"
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
    # Check if skopeo is available
    if ! command -v skopeo &> /dev/null; then
        print_error "skopeo is not installed. Please install it first."
        print_info "Install with: sudo apt install skopeo (Ubuntu/Debian)"
        exit 1
    fi

    # Determine if we need a new commit by comparing container modification time with TAR timestamp
    NEED_COMMIT=true
    if [ -f "$TAR_FILE" ]; then
        # Get container's last modified time (timestamp)
        CONTAINER_MODIFIED_TIME=$(docker inspect --format='{{.State.FinishedAt}}' "$CONTAINER_NAME" 2>/dev/null)
        if [ -z "$CONTAINER_MODIFIED_TIME" ] || [ "$CONTAINER_MODIFIED_TIME" = "0001-01-01T00:00:00Z" ]; then
            # Container never finished (still running or never ran), use Created time
            CONTAINER_MODIFIED_TIME=$(docker inspect --format='{{.Created}}' "$CONTAINER_NAME" 2>/dev/null)
        fi
        
        # Convert to epoch time for comparison
        CONTAINER_EPOCH=$(date -d "$CONTAINER_MODIFIED_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${CONTAINER_MODIFIED_TIME:0:19}" +%s 2>/dev/null)
        TAR_EPOCH=$(stat -c %Y "$TAR_FILE" 2>/dev/null || stat -f %m "$TAR_FILE" 2>/dev/null)
        
        print_info "Container last modified: $(date -d "@$CONTAINER_EPOCH" 2>/dev/null || date -r "$CONTAINER_EPOCH" 2>/dev/null)"
        print_info "TAR created: $(date -d "@$TAR_EPOCH" 2>/dev/null || date -r "$TAR_EPOCH" 2>/dev/null)"
        
        # Check if container was modified after TAR was created
        if [ "$TAR_EPOCH" -ge "$CONTAINER_EPOCH" ]; then
            print_info "TAR is up-to-date with container (no changes detected)"
            NEED_COMMIT=false
        else
            print_warn "Container has been modified since TAR was created"
            NEED_COMMIT=true
        fi
    else
        print_info "No existing TAR file found"
    fi

    # If commit is needed, always create it and rebuild TAR
    if [ "$NEED_COMMIT" = true ]; then
        # If TAR exists and we're rebuilding, handle based on force flag
        if [ -f "$TAR_FILE" ]; then
            if [ "$FORCE_YES" = false ]; then
                read -p "Container modified. Rebuild TAR from container? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_error "Aborted by user"
                    exit 1
                fi
            else
                print_info "Force mode: Rebuilding TAR with new commit"
            fi
            rm -f "$TAR_FILE"
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

        # Create OCI archive using skopeo (always rebuild after new commit)
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
        TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
        print_info "Using existing TAR (Size: $TAR_SIZE)"
    fi
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

# Create consolidated SLURM job script if in HPC prep mode
if [ "$LOCAL_BUILD" = false ]; then
    SLURM_SCRIPT="$HPC_BUILD_DIR/build.slurm"
    cat > "$SLURM_SCRIPT" << 'SLURMEOF'
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --partition=scavenger_l4      
#SBATCH --cpus-per-task=5
#SBATCH --mem=32G
#SBATCH --output=build.out
#SBATCH --error=build.err

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[SLURM BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[SLURM BUILD ERROR]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[SLURM BUILD WARN]${NC} $1"; }

# Get the directory from which sbatch was invoked
SCRIPT_DIR="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$SCRIPT_DIR" || exit 1

print_info "Build directory: $SCRIPT_DIR"
print_info "Job ID: ${SLURM_JOB_ID:-N/A}"

# Find TAR and DEF files
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

IMAGE_NAME=$(basename "$TAR_FILE" .tar)
TARGET_SIF="$SCRIPT_DIR/${IMAGE_NAME}.sif"
TARGET_SANDBOX="$SCRIPT_DIR/${IMAGE_NAME}_sandbox"

print_info "Image name: $IMAGE_NAME"

# Load Apptainer module
print_info "Loading Apptainer module..."

# Check if module command exists
if ! command -v module &>/dev/null; then
    print_error "Module command not found"
    print_error "This HPC system may not use environment modules"
    print_error "Checking if apptainer is available in PATH..."
    if command -v apptainer &>/dev/null; then
        print_info "Found apptainer in PATH: $(which apptainer)"
        APPTAINER_CMD="apptainer"
    elif command -v singularity &>/dev/null; then
        print_info "Found singularity in PATH: $(which singularity)"
        APPTAINER_CMD="singularity"
    else
        print_error "Neither apptainer nor singularity found in PATH"
        print_error "Please ensure Apptainer/Singularity is installed and available"
        exit 1
    fi
else
    # Try loading apptainer module
    if module load apptainer 2>&1; then
        print_info "Loaded apptainer module"
        # Verify it's actually available
        if which apptainer &>/dev/null; then
            print_info "Found apptainer: $(which apptainer)"
            APPTAINER_CMD="apptainer"
        else
            print_warn "Module loaded but apptainer command not found in PATH"
            APPTAINER_CMD=""
        fi
    else
        print_warn "Could not load apptainer module"
        APPTAINER_CMD=""
    fi
    
    # Try singularity if apptainer didn't work
    if [ -z "$APPTAINER_CMD" ]; then
        print_info "Trying singularity module..."
        if module load singularity 2>&1; then
            print_info "Loaded singularity module"
            if which singularity &>/dev/null; then
                print_info "Found singularity: $(which singularity)"
                APPTAINER_CMD="singularity"
            else
                print_warn "Module loaded but singularity command not found in PATH"
                APPTAINER_CMD=""
            fi
        else
            print_error "Could not load singularity module either"
        fi
    fi
    
    # Final check
    if [ -z "$APPTAINER_CMD" ]; then
        print_error "Failed to load apptainer or singularity modules"
        print_error "Available modules:"
        module avail 2>&1 | grep -i "apptainer\|singularity" || echo "  (none found)"
        print_error "Current PATH: $PATH"
        exit 1
    fi
fi

# Get version
APPTAINER_VERSION=$($APPTAINER_CMD --version 2>&1)
print_info "$APPTAINER_CMD version: $APPTAINER_VERSION"

# Build SIF if it doesn't exist or is older than TAR
BUILD_SIF=true
if [ -f "$TARGET_SIF" ]; then
    SIF_TIME=$(stat -c %Y "$TARGET_SIF" 2>/dev/null)
    TAR_TIME=$(stat -c %Y "$TAR_FILE" 2>/dev/null)
    
    if [ "$SIF_TIME" -gt "$TAR_TIME" ]; then
        print_info "SIF is up-to-date, skipping build"
        BUILD_SIF=false
    else
        print_warn "SIF is older than TAR, rebuilding..."
        rm -f "$TARGET_SIF"
    fi
fi

# Build SIF
if [ "$BUILD_SIF" = true ]; then
    print_info "Building SIF: $TARGET_SIF"
    print_info "This may take several minutes..."
    
    BUILD_SUCCESS=false
    
    # Try standard build first (without fakeroot to avoid userid issues)
    print_info "Attempting standard build..."
    if $APPTAINER_CMD build "$TARGET_SIF" "oci-archive://$TAR_FILE" 2>&1 | tee /tmp/apptainer_build_${SLURM_JOB_ID}.log; then
        if [ -f "$TARGET_SIF" ]; then
            BUILD_SUCCESS=true
            print_info "Built successfully with standard method"
        fi
    fi
    
    # Try with --fix-perms if standard failed (avoids userid issues)
    if [ "$BUILD_SUCCESS" = false ]; then
        print_info "Attempting build with --fix-perms..."
        rm -f "$TARGET_SIF" 2>/dev/null
        if $APPTAINER_CMD build --fix-perms "$TARGET_SIF" "oci-archive://$TAR_FILE" 2>&1 | tee /tmp/apptainer_build_${SLURM_JOB_ID}.log; then
            if [ -f "$TARGET_SIF" ]; then
                BUILD_SUCCESS=true
                print_info "Built successfully with --fix-perms"
            fi
        fi
    fi
    
    # Try with --fakeroot as last resort if HPC supports it
    if [ "$BUILD_SUCCESS" = false ]; then
        print_info "Attempting build with --fakeroot..."
        rm -f "$TARGET_SIF" 2>/dev/null
        if $APPTAINER_CMD build --fakeroot "$TARGET_SIF" "oci-archive://$TAR_FILE" 2>&1 | tee /tmp/apptainer_build_${SLURM_JOB_ID}.log; then
            if [ -f "$TARGET_SIF" ]; then
                BUILD_SUCCESS=true
                print_info "Built successfully with --fakeroot"
            fi
        fi
    fi
    
    rm -f /tmp/apptainer_build_${SLURM_JOB_ID}.log
    
    if [ "$BUILD_SUCCESS" = false ]; then
        print_error "Failed to build SIF image"
        exit 1
    fi
    
    SIF_SIZE=$(du -h "$TARGET_SIF" | cut -f1)
    print_info "SIF created: $TARGET_SIF (Size: $SIF_SIZE)"
else
    SIF_SIZE=$(du -h "$TARGET_SIF" | cut -f1)
    print_info "Using existing SIF (Size: $SIF_SIZE)"
fi

# Build sandbox if it doesn't exist or is older than SIF
BUILD_SANDBOX=true
if [ -d "$TARGET_SANDBOX" ]; then
    SANDBOX_TIME=$(stat -c %Y "$TARGET_SANDBOX" 2>/dev/null)
    SIF_TIME=$(stat -c %Y "$TARGET_SIF" 2>/dev/null)
    
    if [ "$SANDBOX_TIME" -gt "$SIF_TIME" ]; then
        print_info "Sandbox is up-to-date"
        BUILD_SANDBOX=false
    else
        print_warn "Sandbox is older than SIF, rebuilding..."
        rm -rf "$TARGET_SANDBOX"
    fi
fi

# Build sandbox
if [ "$BUILD_SANDBOX" = true ]; then
    print_info "Building sandbox: $TARGET_SANDBOX"
    
    if $APPTAINER_CMD build --sandbox "$TARGET_SANDBOX" "$TARGET_SIF"; then
        SANDBOX_SIZE=$(du -sh "$TARGET_SANDBOX" | cut -f1)
        print_info "Sandbox created: $TARGET_SANDBOX (Size: $SANDBOX_SIZE)"
        
        # Test sandbox
        if $APPTAINER_CMD exec "$TARGET_SANDBOX" whoami &>/dev/null; then
            print_info "Sandbox test successful!"
        fi
    else
        print_warn "Sandbox creation failed, but SIF is available"
    fi
else
    SANDBOX_SIZE=$(du -sh "$TARGET_SANDBOX" | cut -f1)
    print_info "Using existing sandbox (Size: $SANDBOX_SIZE)"
fi

print_info "Build complete!"
print_info ""
print_info "Usage examples:"
print_info "  # Using sandbox (RECOMMENDED - fast startup, multiple instances):"
print_info "  apptainer exec --nv $TARGET_SANDBOX <command>"
print_info "  apptainer exec --nv --writable-tmpfs $TARGET_SANDBOX <command>"
print_info ""
print_info "  # Using SIF (fallback if sandbox unavailable):"
print_info "  apptainer exec --nv --unsquash $TARGET_SIF <command>"
SLURMEOF

    chmod +x "$SLURM_SCRIPT"
    print_info "Created SLURM build script: $SLURM_SCRIPT"
    
    # Create README for HPC build
    README_FILE="$HPC_BUILD_DIR/README.md"
    cat > "$README_FILE" << 'READMEEOF'
# HPC Apptainer Build Package

This folder contains everything needed to build an Apptainer SIF and sandbox on the HPC system.

## Contents

- `*.tar` - OCI archive of Docker image
- `*.def` - Apptainer definition file
- `build.slurm` - SLURM job script (builds both SIF and sandbox)
- `README.md` - This file

## Quick Start

### 1. Upload to HPC
```bash
scp -r this_folder/ user@hpc.soton.ac.uk:/scratch/user/builds/
```

### 2. Submit SLURM Job
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

### 3. Find Your Built Images
The built images will be in the same directory as the uploaded files:
```
/path/to/uploaded/folder/image_name.sif        (SIF image)
/path/to/uploaded/folder/image_name_sandbox/   (Sandbox - RECOMMENDED)
```

## What the Build Script Does

1. Locates the .tar and .def files in the current directory
2. Loads the apptainer module (`module load apptainer`)
3. Builds the SIF image (skips if already up-to-date)
4. Builds the sandbox from SIF (fast startup, multiple instances)
5. Tests both images
6. Provides usage examples

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

## Manual Build (if SLURM script fails)

```bash
module load apptainer
cd /path/to/uploaded/folder/

# Build SIF
apptainer build --fakeroot image_name.sif oci-archive://image_name.tar

# Build sandbox from SIF
apptainer build --sandbox image_name_sandbox image_name.sif
```

## Using the Built Images

```bash
# RECOMMENDED: Use sandbox (fast startup, supports multiple instances)
apptainer exec --nv /path/to/folder/image_name_sandbox <command>

# With temporary writes
apptainer exec --nv --writable-tmpfs /path/to/folder/image_name_sandbox <command>

# Bind external Python environment (keeps image small)
apptainer exec --nv \
  --bind /scratch/user/envs/e-swarm:/root/e-swarm \
  /path/to/folder/image_name_sandbox <command>

# Interactive shell
apptainer shell --nv /path/to/folder/image_name_sandbox

# Fallback: Use SIF (slower startup if FUSE unavailable)
apptainer exec --nv --unsquash /path/to/folder/image_name.sif <command>
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
    print_info "  - build.slurm (SLURM job script - builds SIF and sandbox)"
    print_info "  - README.md (Instructions)"
    echo ""
fi
