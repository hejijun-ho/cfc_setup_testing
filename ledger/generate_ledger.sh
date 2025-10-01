#!/bin/bash
# This script builds all necessary components and runs the launcher to start the
# confidential ledger in a virtualized TEE, keeping it running until manually stopped.
# It follows the conventions from `oak/justfile` for running restricted kernel applications.

set -e # Exit script on any command failure

CFC_DIR="/mydata/google_parfait_build/confidential-federated-compute"
OAK_DIR="/mydata/google_parfait_build/oak"
ARTIFACTS_DIR="/mydata/google_parfait_build/artifacts/binaries"
QEMU_PATH="/usr/bin/qemu-system-x86_64" # Verified path

# --- Step 0: Ensure Environment is Ready ---
echo "[0/2] Ensuring build environment is ready..."

# Ensure strip-nondeterminism is available
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

# --- Step 1: Build and Copy All Artifacts ---
echo "[1/2] Building and copying all necessary artifacts to $ARTIFACTS_DIR..."
mkdir -p "$ARTIFACTS_DIR"

# Define Bazel targets
LEDGER_APP_TARGET="//ledger_enclave_app:ledger_enclave_app"
LAUNCHER_TARGET="//oak_restricted_kernel_launcher:main"
BIOS_TARGET="//stage0_bin:stage0_bin"
KERNEL_TARGET="//oak_restricted_kernel_wrapper:oak_restricted_kernel_wrapper_virtio_console_channel_bin"
INITRD_TARGET="//enclave_apps/oak_orchestrator"

# Define destination names for artifacts
LEDGER_APP_DEST="ledger_enclave_app"
LAUNCHER_DEST="oak_restricted_kernel_launcher"
BIOS_DEST="stage0_bin"
KERNEL_DEST="oak_restricted_kernel_wrapper_virtio_console_channel_bin"
INITRD_DEST="oak_orchestrator" 

# Build and copy Ledger application
(
    cd "$CFC_DIR"
    export PATH="$HOME/.nix-profile/bin:$PATH"
    bazelisk build "$LEDGER_APP_TARGET"
    SRC_PATH=$(bazelisk cquery "$LEDGER_APP_TARGET" --output=files)
    if [ -z "$SRC_PATH" ]; then
        echo "❌ Error: bazelisk cquery failed to find path for $LEDGER_APP_TARGET" >&2
        exit 1
    fi
    cp -f "$SRC_PATH" "$ARTIFACTS_DIR/$LEDGER_APP_DEST"
)

# Build and copy Oak components
(
    cd "$OAK_DIR"
    nix develop .#bazelShell --command bazelisk build \
        "$LAUNCHER_TARGET" \
        "$BIOS_TARGET" \
        "$KERNEL_TARGET" \
        "$INITRD_TARGET"

    copy_artifact() {
        local target="$1"
        local dest_name="$2"
        local src_path
        src_path=$(nix develop .#bazelShell --command bazelisk cquery "$target" --output=files)
        if [ -z "$src_path" ]; then
            echo "❌ Error: bazelisk cquery failed to find path for $target" >&2
            exit 1
        fi
        echo "    Copying artifact for $target"
        cp -f "$src_path" "$ARTIFACTS_DIR/$dest_name"
    }

    copy_artifact "$LAUNCHER_TARGET" "$LAUNCHER_DEST"
    copy_artifact "$BIOS_TARGET" "$BIOS_DEST"
    copy_artifact "$KERNEL_TARGET" "$KERNEL_DEST"
    copy_artifact "$INITRD_TARGET" "$INITRD_DEST"
)
echo "✅ All artifacts built and copied."

# --- Step 2: Run QEMU VM ---
echo "[2/2] Starting QEMU VM for Ledger application..."

# Define artifact paths
LEDGER_APP_EXEC_PATH="$ARTIFACTS_DIR/$LEDGER_APP_DEST"
LAUNCHER_EXEC_PATH="$ARTIFACTS_DIR/$LAUNCHER_DEST"
BIOS_PATH="$ARTIFACTS_DIR/$BIOS_DEST"
KERNEL_PATH="$ARTIFACTS_DIR/$KERNEL_DEST"
INITRD_PATH="$ARTIFACTS_DIR/$INITRD_DEST"
# INITRD_PATH="/tmp/oak_orchestrator_initramfs.cpio"

# Validate paths
for f in "$LEDGER_APP_EXEC_PATH" "$LAUNCHER_EXEC_PATH" "$BIOS_PATH" "$KERNEL_PATH" "$INITRD_PATH" "$QEMU_PATH"; do
  if [ ! -f "$f" ]; then
    echo "❌ Error: Required artifact not found: $f" >&2
    exit 1
  fi
done
echo "✅ All artifacts found."

# Find an available port for the Ledger TEE
LEDGER_HOST_PORT="46787" #$(python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
LEDGER_VM_PORT="8080" # Ledger app listens on 8080 inside VM

echo "Starting the launcher with all required components..."
echo "The Ledger service will be available at http://127.0.0.1:$LEDGER_HOST_PORT"
echo "Press Ctrl+C to shut down the ledger service."

# Execute the launcher
##                   oak_restricted_kernel_launcher   ==                     stage0_bin    oak_restricted_kernel_wrapper_virtio_console_channel_bin                                                                                                           
##                                                                                                                                     oak_orchestrator            ledger_enclave_app
sudo RUST_LOG=debug "$LAUNCHER_EXEC_PATH"  --vmm-binary="$QEMU_PATH"     --bios-binary="$BIOS_PATH"     --kernel="$KERNEL_PATH"     --initrd="$INITRD_PATH"     --app-binary="$LEDGER_APP_EXEC_PATH"     --memory-size="8G"   #--gdb=1234 #used

# sudo RUST_LOG=debug "$LAUNCHER_EXEC_PATH" --vmm-binary="$QEMU_PATH" --bios-binary="$BIOS_PATH" --kernel="$KERNEL_PATH" --initrd="$INITRD_PATH" --app-binary="$LEDGER_APP_EXEC_PATH" --memory-size="2G"


# cd oak
# just wasm-crates
# # just run-oak-functions-launcher wasm_target port lookup_data_path
# just run-oak-functions-launcher 


# sudo strace -f -e trace=network -s 1000 "$LAUNCHER_EXEC_PATH" \
#   --vmm-binary="$QEMU_PATH" \
#   --bios-binary="$BIOS_PATH" \
#   --kernel="$KERNEL_PATH" \
#   --initrd="$INITRD_PATH" \
#   --app-binary="$LEDGER_APP_EXEC_PATH" \
#   --memory-size="8G"

echo "🎉 Ledger service has been shut down."
