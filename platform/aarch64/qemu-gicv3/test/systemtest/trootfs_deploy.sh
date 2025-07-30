#!/bin/bash
set -e
set -x            # Print commands for debugging

# =================================================================
# ### Dynamic Configuration from CI Environment ###
# =================================================================
# This script is generic. It reads ARCH and BOARD
# from the environment variables set in the CI workflow.

# Check if ARCH and BOARD are set, exit if not.
if [ -z "$ARCH" ] || [ -z "$BOARD" ]; then
    echo "ERROR: ARCH and BOARD environment variables must be set." >&2
    exit 1
fi

# Set architecture-specific variables based on ARCH
if [ "$ARCH" = "aarch64" ]; then
    TOOLCHAIN_PREFIX="aarch64-linux-gnu-"
    MAKE_ARCH="arm64"  # The Makefile for hvisor-tool uses 'arm64' for aarch64
    LINUX_REPO="https://github.com/CHonghaohao/linux_5.4.git"
elif [ "$ARCH" = "riscv64" ]; then
    TOOLCHAIN_PREFIX="riscv64-linux-gnu-"
    MAKE_ARCH="riscv"
    LINUX_REPO="https://github.com/CHonghaohao/linux_v6.10-rc1.git"
else
    echo "ERROR: Unsupported architecture: $ARCH" >&2
    exit 1
fi

# =================================================================
# ### Generic Environment Configuration ###
# =================================================================
# All paths are now constructed dynamically using the $ARCH and $BOARD variables.

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
PLATFORM_DIR="${WORKSPACE_ROOT}/platform/${ARCH}/${BOARD}"
VIRDISK_DIR="${PLATFORM_DIR}/image/virtdisk"
ROOTFS_DIR="${VIRDISK_DIR}/rootfs"
LINUX_KERNEL_DIR=$(find "${VIRDISK_DIR}" -maxdepth 1 -type d -name "linux_*" | head -n 1) # Find kernel dir
HVISOR_TOOL_DIR="${VIRDISK_DIR}/hvisor-tool"
CONFIG_DIR="${PLATFORM_DIR}/configs"
TEST_DIR="${PLATFORM_DIR}/test/systemtest"
DTS_DIR="${PLATFORM_DIR}/image/dts"

# ========================
# Function Definitions
# ========================

mount_rootfs() {
    echo "=== Mounting root filesystem ==="
    sudo mkdir -p "${ROOTFS_DIR}"
    if ! sudo mount "${VIRDISK_DIR}/rootfs1.ext4" "${ROOTFS_DIR}"; then
        echo "ERROR: Failed to mount rootfs" >&2
        exit 1
    fi
}

prepare_sources() {
    echo "=== Cloning required repositories for $ARCH ==="
    if [ ! -d "$LINUX_KERNEL_DIR" ]; then
        echo "Cloning Linux kernel from ${LINUX_REPO}"
        git clone "${LINUX_REPO}"
    fi
    if [ ! -d "${HVISOR_TOOL_DIR}" ]; then
        echo "Cloning hvisor-tool"
        git clone https://github.com/syswonder/hvisor-tool.git "${HVISOR_TOOL_DIR}"
    fi
    # Update kernel directory path after potential clone
    LINUX_KERNEL_DIR=$(find "${VIRDISK_DIR}" -maxdepth 1 -type d -name "linux_*" | head -n 1)
}

build_hvisor_tool() {
    echo "=== Building hvisor components for $ARCH ==="
    cd "${HVISOR_TOOL_DIR}"

    # The make command now uses the variables we defined at the top.
    make all ARCH=${MAKE_ARCH} \
        CROSS_COMPILE=${TOOLCHAIN_PREFIX} \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}"
}

deploy_artifacts() {
    echo "=== Deploying build artifacts to /home/${ARCH} ==="
    local dest_dir="${ROOTFS_DIR}/home/${ARCH}"
    local test_dest="${dest_dir}/test"

    sudo mkdir -p "${test_dest}/testcase"

    # Copy main components
    sudo cp -v "${HVISOR_TOOL_DIR}/tools/hvisor" "${dest_dir}/"
    sudo cp -v "${HVISOR_TOOL_DIR}/driver/hvisor.ko" "${dest_dir}/"
    # Device Tree & Configurations
    sudo cp -v "${DTS_DIR}/zone1-linux.dtb" "${dest_dir}/zone1-linux.dtb"
    sudo cp -v "${CONFIG_DIR}/zone1-linux.json" "${dest_dir}/zone1-linux.json"
    sudo cp -v "${CONFIG_DIR}/zone1-linux-virtio.json" "${dest_dir}/zone1-linux-virtio.json"
    # Test artifacts
    sudo cp -v ${TEST_DIR}/testcase/* "${test_dest}/testcase/"
    sudo cp -v "${TEST_DIR}/textract_dmesg.sh" "${test_dest}/"
    sudo cp -v "${TEST_DIR}/tresult.sh" "${test_dest}/"
    # Boot zone1 shells
    sudo cp -v "${TEST_DIR}/boot_zone1.sh" "${dest_dir}/"
    sudo cp -v "${TEST_DIR}/screen_zone1.sh" "${dest_dir}/"

    # Verify deployment
    echo "=== Deployed files list ==="
    sudo find "${dest_dir}" -ls
}

# =================================================================
# ### Generic Main Execution Flow ###
# =================================================================
(
    cd "${VIRDISK_DIR}"

    # Setup environment
    # mount_rootfs # You can re-enable this later
    prepare_sources

    # Build process
    if ! build_hvisor_tool; then
        echo "ERROR: Build failed" >&2
        exit 1
    fi

    # Deployment
    # deploy_artifacts # You can re-enable this later

    # Cleanup
    echo "=== Unmounting rootfs ==="
    # sudo umount "${ROOTFS_DIR}" # You can re-enable this later
) || exit 1