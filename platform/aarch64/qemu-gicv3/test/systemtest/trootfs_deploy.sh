#!/bin/bash
set -e
set -x            # Print commands for debugging

# ========================
# Environment Configuration (aarch64 specific)
# ========================
WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ROOTFS_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/image/virtdisk/rootfs"
LINUX_KERNEL_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/image/virtdisk/linux_5.4"
HVISOR_TOOL_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/image/virtdisk/hvisor-tool"
CONFIG_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/configs"
TEST_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/test/systemtest"
DTS_DIR="${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/image/dts"

# ========================
# Function Definitions
# ========================

mount_rootfs() {
    echo "=== Mounting root filesystem ==="
    sudo mkdir -p "${ROOTFS_DIR}"
    if ! sudo mount rootfs1.ext4 "${ROOTFS_DIR}"; then
        echo "ERROR: Failed to mount rootfs" >&2
        exit 1
    fi
}

prepare_sources() {
    echo "=== Cloning required repositories ==="
    # 克隆 aarch64 需要的正确内核版本
    if [ ! -d "linux_5.4" ]; then
        git clone https://github.com/CHonghaohao/linux_5.4.git || return 1
    fi
    if [ ! -d "hvisor-tool" ]; then
        git clone https://github.com/syswonder/hvisor-tool.git || return 1
    fi
}

build_hvisor_tool() {
    echo "=== Building hvisor components ==="
    cd "${HVISOR_TOOL_DIR}"

    local MAKE_ARCH=""

    case "${ARCH}" in
        riscv64)
            # riscv64 的配置
            export CC='riscv64-linux-gnu-gcc --sysroot=/usr/riscv64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0'
            MAKE_ARCH="riscv"
            ;;
        aarch64)
            # 【终极修正】将所有编译标志直接注入 CC 变量。
            export CC='aarch64-linux-gnu-gcc --sysroot=/usr/aarch64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0'
            # 将 CI 的标准架构名 'aarch64' 翻译为 Makefile 期望的 'arm64'
            MAKE_ARCH="arm64"
            ;;
    esac

    # 【终极修正】调用 make 时，将 CFLAGS 强制设置为空，防止 Makefile 内部的任何污染。
    # 所有的编译环境控制现在都由我们上面定义的 CC 变量全权负责。
    make -e all \
        ARCH=${MAKE_ARCH} \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}" \
        CFLAGS="" \
        MAKE='make -e'
}

deploy_artifacts() {
    # ... 此函数内容无需修改，它使用 aarch64 特定的路径 ...
    echo "=== Deploying build artifacts ==="
    local dest_dir="${ROOTFS_DIR}/home/arm64"
    local test_dest="${dest_dir}/test"
    sudo mkdir -p "${dest_dir}"
    sudo mkdir -p "${test_dest}/testcase"
    sudo cp -v "${HVISOR_TOOL_DIR}/tools/hvisor" "${dest_dir}/"
    sudo cp -v "${HVISOR_TOOL_DIR}/driver/hvisor.ko" "${dest_dir}/"
    sudo cp -v "${DTS_DIR}/zone1-linux.dtb" "${dest_dir}/zone1-linux.dtb"
    sudo cp -v "${CONFIG_DIR}/zone1-linux.json" "${dest_dir}/zone1-linux.json"
    sudo cp -v "${CONFIG_DIR}/zone1-linux-virtio.json" "${dest_dir}/zone1-linux-virtio.json"
    sudo cp -v ${TEST_DIR}/testcase/* "${test_dest}/testcase/"
    sudo cp -v "${TEST_DIR}/textract_dmesg.sh" "${test_dest}/"
    sudo cp -v "${TEST_DIR}/tresult.sh" "${test_dest}/"
    sudo cp -v "${TEST_DIR}/boot_zone1.sh" "${dest_dir}/"
    sudo cp -v "${TEST_DIR}/screen_zone1.sh" "${dest_dir}/"
    echo "=== Deployed files list ==="
    sudo find "${dest_dir}" -ls
}

# ========================
# Main Execution Flow (aarch64 specific)
# ========================
(
    cd "${WORKSPACE_ROOT}/platform/aarch64/qemu-gicv3/image/virtdisk"
    mount_rootfs
    prepare_sources
    if ! build_hvisor_tool; then
        echo "ERROR: Build failed" >&2
        exit 1
    fi
    deploy_artifacts
    echo "=== Unmounting rootfs ==="
    sudo umount "${ROOTFS_DIR}"
) || exit 1