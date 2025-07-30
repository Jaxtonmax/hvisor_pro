#!/bin/bash
set -e
set -x            # Print commands for debugging

# ========================
# Environment Configuration
# ========================
WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ROOTFS_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/virtdisk/rootfs"
LINUX_KERNEL_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/virtdisk/linux_v6.10-rc1"
HVISOR_TOOL_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/virtdisk/hvisor-tool"
CONFIG_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/configs"
TEST_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/test/systemtest"
DTS_DIR="${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/dts"

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
    # 克隆编译所需的 hvisor-tool 和内核源码
    # 这些仓库将被克隆到当前目录，也就是 virtdisk 目录
    if [ ! -d "linux_v6.10-rc1" ]; then
        git clone https://github.com/CHonghaohao/linux_v6.10-rc1.git || return 1
    fi
    if [ ! -d "hvisor-tool" ]; then
        git clone https://github.com/syswonder/hvisor-tool.git || return 1
    fi
}

build_hvisor_tool() {
    echo "=== Building hvisor components ==="
    # 进入 hvisor-tool 源码目录，这个目录是由 prepare_sources 克隆下来的
    cd "${HVISOR_TOOL_DIR}"

    local CFLAGS_EXTRA=""

    case "${ARCH}" in
        riscv64)
            export CC="riscv64-linux-gnu-gcc --sysroot=/usr/riscv64-linux-gnu"
            # 【正确配置】只使用 --sysroot，移除所有手动的 -I 系统路径
            CFLAGS_EXTRA="--sysroot=/usr/riscv64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
            ;;
        aarch64)
            export CC="aarch64-linux-gnu-gcc --sysroot=/usr/aarch64-linux-gnu"
            CFLAGS_EXTRA="--sysroot=/usr/aarch64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
            ;;
    esac

    # 【正确配置】使用 ${ARCH} 变量来动态设置架构
    make -e all \
        ARCH=${ARCH} \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}" \
        "CFLAGS+=${CFLAGS_EXTRA}" \
        MAKE='make -e'
}

deploy_artifacts() {
    # ... 此函数内容无需修改，保持原样即可 ...
    echo "=== Deploying build artifacts ==="
    local dest_dir="${ROOTFS_DIR}/home/riscv64"
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
# Main Execution Flow
# ========================
(
    cd "${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/virtdisk"
    
    mount_rootfs
    
    # 【关键步骤】必须调用 prepare_sources 来克隆 hvisor-tool 仓库
    prepare_sources
    
    if ! build_hvisor_tool; then
        echo "ERROR: Build failed" >&2
        exit 1
    fi
    
    deploy_artifacts

    echo "=== Unmounting rootfs ==="
    sudo umount "${ROOTFS_DIR}"
) || exit 1