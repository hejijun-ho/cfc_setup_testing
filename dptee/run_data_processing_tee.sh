#!/bin/bash
set -e

# This script runs a data processing application in a simulated, container-based TEE.
# It follows the conventions from `oak/justfile` for running containerized applications
# without requiring specific hardware features like SEV-SNP.

# --- Configuration ---
CFC_DIR="/mydata/google_parfait_build/confidential-federated-compute"
OAK_DIR="/mydata/google_parfait_build/oak"
ARTIFACTS_DIR="/mydata/google_parfait_build/artifacts/binaries"
QEMU_PATH="/usr/bin/qemu-system-x86_64" # Verified path

# --- Step 0: Ensure Environment is Ready ---
echo "[0/3] Ensuring build environment is ready..."
# The stage1 CPIO build requires the `strip-nondeterminism` tool.
# We install it here to ensure it's available.
# This command requires sudo privileges.
if ! command -v strip-nondeterminism &> /dev/null
then
    echo "'strip-nondeterminism' not found. Installing 'dh-strip-nondeterminism'..."
    sudo apt-get update && sudo apt-get install -y dh-strip-nondeterminism
else
    echo "'strip-nondeterminism' is already installed."
fi

# Ensure vhost_vsock kernel module is loaded for virtio-vsock communication.
echo "Loading vhost_vsock kernel module..."
sudo modprobe vhost_vsock || echo "Warning: Failed to load vhost_vsock module. vsock communication might not work."

# Define Bazel targets for a containerized environment
CFC_APP_TARGET="//containers/fed_sql:oci_runtime_bundle"
OAK_LAUNCHER_TARGET="//oak_containers/launcher"
OAK_STAGE0_TARGET="//stage0_bin"
OAK_KERNEL_TARGET="//oak_containers/kernel"
OAK_STAGE1_TARGET="//oak_containers/stage1_bin:stage1.cpio"
OAK_SYSTEM_IMAGE_TARGET="//oak_containers/system_image:oak_containers_system_image"

# Define destination names for artifacts
CFC_APP_DEST="data_processing_container_bundle.tar"
OAK_LAUNCHER_DEST="oak_containers_launcher"
OAK_STAGE0_DEST="stage0_bin"
OAK_KERNEL_DEST="oak_containers_kernel"
OAK_STAGE1_DEST="oak_containers_stage1.cpio"
OAK_SYSTEM_IMAGE_DEST="oak_containers_system_image.tar.xz"

# Additional parameters for container launcher
RAMDRIVE_SIZE="1000000" # 1MB
MEMORY_SIZE="2G"

# --- Step 1: Build and Copy Artifacts ---
echo "[1/3] Building and copying containerized artifacts to $ARTIFACTS_DIR..."
mkdir -p "$ARTIFACTS_DIR"

# Build and copy CFC application bundle
echo "Building CFC app bundle..."
(
    cd "$CFC_DIR"
    export PATH="$HOME/.nix-profile/bin:$PATH"
    bazelisk build "$CFC_APP_TARGET"
    SRC_PATH=$(bazelisk cquery "$CFC_APP_TARGET" --output=files)
    if [ -z "$SRC_PATH" ]; then
        echo "❌ Error: bazelisk cquery failed to find path for $CFC_APP_TARGET" >&2
        exit 1
    fi
    cp -f "$SRC_PATH" "$ARTIFACTS_DIR/$CFC_APP_DEST"
)

# Build and copy Oak container components
echo "Building Oak container components..."
(
    cd "$OAK_DIR"
    # Build all targets in one go for efficiency
    nix develop .#containers --command bazelisk build \
        "$OAK_LAUNCHER_TARGET" \
        "$OAK_STAGE0_TARGET" \
        "$OAK_KERNEL_TARGET" \
        "$OAK_STAGE1_TARGET" \
        "$OAK_SYSTEM_IMAGE_TARGET"

    copy_artifact() {
        local target="$1"
        local dest_name="$2"
        local src_path
        src_path=$(nix develop .#containers --command bazelisk cquery "$target" --output=files)
        if [ -z "$src_path" ]; then
            echo "❌ Error: bazelisk cquery failed to find path for $target" >&2
            exit 1
        fi
        echo "    Copying artifact for $target"
        cp -f "$src_path" "$ARTIFACTS_DIR/$dest_name"
    }

    copy_artifact "$OAK_LAUNCHER_TARGET" "$OAK_LAUNCHER_DEST"
    copy_artifact "$OAK_STAGE0_TARGET" "$OAK_STAGE0_DEST"
    copy_artifact "$OAK_KERNEL_TARGET" "$OAK_KERNEL_DEST"
    copy_artifact "$OAK_STAGE1_TARGET" "$OAK_STAGE1_DEST"
    copy_artifact "$OAK_SYSTEM_IMAGE_TARGET" "$OAK_SYSTEM_IMAGE_DEST"
)
echo "✅ All artifacts built and copied."

# --- Step 2: Define Artifact Paths ---
echo "[2/3] Locating artifacts for launcher..."
LAUNCHER_EXEC_PATH="$ARTIFACTS_DIR/$OAK_LAUNCHER_DEST"
STAGE0_PATH="$ARTIFACTS_DIR/$OAK_STAGE0_DEST"
KERNEL_PATH="$ARTIFACTS_DIR/$OAK_KERNEL_DEST"
STAGE1_PATH="$ARTIFACTS_DIR/$OAK_STAGE1_DEST"
SYSTEM_IMAGE_PATH="$ARTIFACTS_DIR/$OAK_SYSTEM_IMAGE_DEST"
CONTAINER_BUNDLE_PATH="$ARTIFACTS_DIR/$CFC_APP_DEST"

# Validate paths
for f in "$LAUNCHER_EXEC_PATH" "$STAGE0_PATH" "$KERNEL_PATH" "$STAGE1_PATH" "$SYSTEM_IMAGE_PATH" "$CONTAINER_BUNDLE_PATH" "$QEMU_PATH"; do
  if [ ! -f "$f" ]; then
    echo "❌ Error: Required artifact not found: $f" >&2
    exit 1
  fi
done
echo "✅ All artifacts found."

# --- Step 3: Run QEMU VM ---
echo "[3/3] Starting QEMU VM for containerized application..."

# Note: We are not using sudo here, as the container launcher in simulation mode
# might not require it. If you encounter permission errors, you might need to add it back.
RUST_LOG=debug GLOG_v=3 "$LAUNCHER_EXEC_PATH" \
    --vmm-binary="$QEMU_PATH" \
    --stage0-binary="$STAGE0_PATH" \
    --kernel="$KERNEL_PATH" \
    --initrd="$STAGE1_PATH" \
    --system-image="$SYSTEM_IMAGE_PATH" \
    --container-bundle="$CONTAINER_BUNDLE_PATH" \
    --ramdrive-size="$RAMDRIVE_SIZE" \
    --memory-size="$MEMORY_SIZE"

echo "🎉 Data Processing TEE VM has exited."
