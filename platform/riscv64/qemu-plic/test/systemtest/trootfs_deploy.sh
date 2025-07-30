#!/bin/bash
set -e
set -x            # Print commands for debugging

# =================================================================
# ### NEW: Dynamic Configuration from CI Environment ###
# =================================================================
# This section makes the script generic. It reads ARCH and BOARD
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
elif [ "$ARCH" = "riscv64" ]; then
    TOOLCHAIN_PREFIX="riscv64-linux-gnu-"
    MAKE_ARCH="riscv"
else
    echo "ERROR: Unsupported architecture: $ARCH" >&2
    exit 1
fi

# =================================================================
# ### MODIFIED: Generic Environment Configuration ###
# =================================================================
# All paths are now constructed dynamically using the $ARCH and $BOARD variables.

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
PLATFORM_DIR="${WORKSPACE_ROOT}/platform/${ARCH}/${BOARD}"
ROOTFS_DIR="${PLATFORM_DIR}/image/virtdisk/rootfs"
# NOTE: Ensure the kernel directory name is correct for each architecture.
# Based on your logs, it might be different. You may need to adjust this logic.
LINUX_KERNEL_DIR="${PLATFORM_DIR}/image/virtdisk/linux_*" # Using a wildcard to be more robust
HVISOR_TOOL_DIR="${PLATFORM_DIR}/image/virtdisk/hvisor-tool"
CONFIG_DIR="${PLATFORM_DIR}/configs"
TEST_DIR="${PLATFORM_DIR}/test/systemtest"
DTS_DIR="${PLATFORM_DIR}/image/dts"

# ========================
# Function Definitions
# ========================

mount_rootfs() {
    echo "=== Mounting root filesystem ==="
    sudo mkdir -p "${ROOTFS_DIR}"
    # NOTE: The rootfs image name might also need to be generic if it differs
    if ! sudo mount rootfs1.ext4 "${ROOTFS_DIR}"; then
        echo "ERROR: Failed to mount rootfs" >&2
        exit 1
    fi
}

prepare_sources() {
    echo "=== Cloning required repositories ==="
    # NOTE: These might need to be different versions per architecture.
    # For now, we assume they are the same.
    if [ ! -d "linux_*" ]; then
        git clone https://github.com/CHonghaohao/linux_v6.10-rc1.git
    fi
    if [ ! -d "hvisor-tool" ]; then
        git clone https://github.com/syswonder/hvisor-tool.git
    fi
}

# ### MODIFIED: Generic build_hvisor_tool function ###
build_hvisor_tool() {
    echo "=== Building hvisor components ==="
    cd "${HVISOR_TOOL_DIR}"

    # The make command now uses the variables we defined at the top.
    make all ARCH=${MAKE_ARCH} \
        CROSS_COMPILE=${TOOLCHAIN_PREFIX} \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}"
}

# ### MODIFIED: Generic deploy_artifacts function ###
deploy_artifacts() {
    echo "=== Deploying build artifacts ==="
    # The destination directory inside the rootfs should also be dynamic.
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
# ### MODIFIED: Generic Main Execution Flow ###
# =================================================================
(
    # The main working directory is now also dynamic.
    cd "${PLATFORM_DIR}/image/virtdisk"

    # Setup environment
    # mount_rootfs # Temporarily disable mount/unmount for CI debugging if needed
    prepare_sources

    # Build process
    if ! build_hvisor_tool; then
        echo "ERROR: Build failed" >&2
        exit 1
    fi

    # Deployment
    # deploy_artifacts # Temporarily disable deploy for CI debugging if needed

    # Cleanup
    echo "=== Unmounting rootfs ==="
    # sudo umount "${ROOTFS_DIR}" # Temporarily disable mount/unmount
) || exit 1