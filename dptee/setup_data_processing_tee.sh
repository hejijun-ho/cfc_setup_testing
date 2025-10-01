#!/bin/bash
set -e

# --- Initial Setup ---
echo "🚀 安裝系統依賴..."
sudo apt update && sudo apt install -y git build-essential curl protobuf-compiler clang pkg-config rsync psmisc

# --- Rust --- 
if ! command -v cargo &> /dev/null; then
    echo "🚀 安裝 Rust..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    . "$HOME/.cargo/env"
else
    echo "✅ Rust 已安裝。"
fi
. "$HOME/.cargo/env"

# --- Nix Installation using Bind Mount (The Correct Way) ---

# 1. Full Cleanup of Previous Attempts
echo "🚀 徹底清理任何舊的 Nix 安裝和設定..."
sudo systemctl stop nix-daemon.socket nix-daemon.service determinate-nixd.socket determinate-nixd.service || true
if sudo fuser -km /nix 2>/dev/null; then
    echo "⚠️ 偵測到有程序正在使用 /nix，已嘗試終止。"
fi
sudo umount -lf /nix || true
if [ -f "/nix/nix-installer" ]; then
    sudo /nix/nix-installer uninstall --no-confirm || true
fi
sudo rm -rf /nix
sudo rm -rf /mydata/nix
sudo sed -i "\|/mydata/nix /nix|d" /etc/fstab

# 2. Create Mount Points and Perform Bind Mount
echo "🚀 建立掛載點並執行 bind mount..."
sudo mkdir -p /mydata/nix
sudo mkdir -p /nix
sudo mount --bind /mydata/nix /nix

# 3. Make the Bind Mount Permanent
FSTAB_ENTRY="/mydata/nix /nix none bind 0 0"
if ! sudo grep -Fxq "$FSTAB_ENTRY" /etc/fstab; then
    echo "🚀 將 bind mount 設定寫入 /etc/fstab 使其永久生效..."
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
else
    echo "✅ fstab 設定已存在。"
fi

# 4. Run the Standard Nix Installer
NIX_PROFILE_SCRIPT="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
if [ ! -f "$NIX_PROFILE_SCRIPT" ]; then
    echo "🚀 執行標準 Nix 安裝程式..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    echo "💡 Nix 已安裝。"
else
    echo "✅ Nix 已安裝於 /mydata/nix (透過 bind mount)。"
fi

# 5. Source Nix environment and configure .bashrc
. "$NIX_PROFILE_SCRIPT"
NIX_BASHRC_LINE="if [ -f $NIX_PROFILE_SCRIPT ]; then . $NIX_PROFILE_SCRIPT; fi"
BASHRC_SED_SCRIPT_1="s|if \[ -f $NIX_PROFILE_SCRIPT \]; then \. $NIX_PROFILE_SCRIPT; fi||g"
BASHRC_SED_SCRIPT_2="s|/etc/profile.d/nix.sh||g"
sed -i -e "$BASHRC_SED_SCRIPT_1" "$HOME/.bashrc"
sed -i -e "$BASHRC_SED_SCRIPT_2" "$HOME/.bashrc"

if ! grep -Fxq "$NIX_BASHRC_LINE" "$HOME/.bashrc"; then
    echo "🚀 加入 Nix 環境到 ~/.bashrc..."
    echo "$NIX_BASHRC_LINE" >> "$HOME/.bashrc"
fi

# --- Environment Configuration (using the new Nix) ---

# Enable flakes
echo "🚀 啟用 Nix flakes..."
mkdir -p "$HOME/.config/nix"
echo "experimental-features = nix-command flakes" > "$HOME/.config/nix/nix.conf"

# Install direnv, nix-direnv, and bazelisk using Nix
echo "🚀 使用 Nix 安裝 direnv, nix-direnv, bazelisk... 陳"
nix profile install nixpkgs#direnv nixpkgs#nix-direnv nixpkgs#bazelisk

# Clean up old/stale .bashrc entries
echo "🚀 清理舊的 bashrc 設定..."
sed -i '/nix-direnv.*direnvrc/d' "$HOME/.bashrc"
sed -i '/direnv hook/d' "$HOME/.bashrc"

# Add direnv hook to .bashrc
DIRENV_HOOK='eval "$(direnv hook bash)"'
echo "🚀 鉤入 direnv 到 ~/.bashrc..."
echo "$DIRENV_HOOK" >> "$HOME/.bashrc"

# Add nix-direnv to .bashrc
NIX_DIRENV_PATH=$(nix eval --raw nixpkgs#nix-direnv.outPath)
echo "🚀 加入 nix-direnv 到 ~/.bashrc..."
echo "source $NIX_DIRENV_PATH/share/nix-direnv/direnvrc" >> "$HOME/.bashrc"

# Activate environment for the current session
echo "🚀 啟用 direnv hook..."
eval "$(direnv hook bash)"
echo "🚀 立刻 source nix-direnv 設定檔..."
. "$NIX_DIRENV_PATH/share/nix-direnv/direnvrc"

# --- Project Build ---
# Set Bazel cache to /mydata globally for this user
BAZEL_CACHE_DIR="/mydata/bazel_cache"
echo "🚀 設定全域 Bazel 快取路徑到 $BAZEL_CACHE_DIR..."
mkdir -p "$BAZEL_CACHE_DIR"
echo "startup --output_user_root=$BAZEL_CACHE_DIR" > "$HOME/.bazelrc"

# Set build directory
BUILD_DIR="/mydata/google_parfait_build"
echo "🚀 將在 $BUILD_DIR 中進行建置..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone Project Oak
if [ ! -d "oak" ]; then
    echo "🚀 Clone Project Oak..."
    git clone https://github.com/project-oak/oak.git
fi
cd oak
echo "🚀 執行 direnv allow..."
direnv allow

echo "🚀 建置 Oak Stage0..."
nix develop .#bazelShell --command bazel build //stage0_bin
cd ..

# Clone Confidential Federated Compute
if [ ! -d "confidential-federated-compute" ]; then
    echo "🚀 Clone Confidential Federated Compute..."
    git clone https://github.com/google-parfait/confidential-federated-compute.git
fi
cd confidential-federated-compute
echo "🚀 建置 Data Processing TEE binary (containers/fed_sql:main)..."
bazelisk build //containers/fed_sql:main
cd ..

echo "✅ Data Processing TEE 機器建置完成"
echo "💡 請手動執行："
echo "    source ~/.bashrc"
echo "    cd /mydata/google_parfait_build/oak && direnv reload"
echo "    sudo usermod -a -G kvm $USER (then re-login)"