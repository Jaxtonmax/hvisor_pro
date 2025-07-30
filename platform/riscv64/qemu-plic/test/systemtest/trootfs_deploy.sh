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
    # 如果目录已存在，假设代码已由CI的checkout步骤准备好，跳过clone
    if [ ! -d "linux_v6.10-rc1" ]; then
        git clone https://github.com/CHonghaohao/linux_v6.10-rc1.git || return 1
    fi
    if [ ! -d "hvisor-tool" ]; then
        git clone https://github.com/syswonder/hvisor-tool.git || return 1
    fi
}

build_hvisor_tool() {
    echo "=== Building hvisor components ==="
    cd "${HVISOR_TOOL_DIR}"

    local CFLAGS_EXTRA=""

    case "${ARCH}" in
        riscv64)
            # 设置编译器和 sysroot
            export CC="riscv64-linux-gnu-gcc --sysroot=/usr/riscv64-linux-gnu"
            # 准备需要强制注入的 CFLAGS。
            # --sysroot: 正确指定交叉编译的系统根。编译器会自动在此根下查找头文件和库。
            #            【重要】避免手动添加 -I 来指定系统头文件路径 (如 -I/usr/riscv64-linux-gnu/include)，
            #            这会干扰编译器的标准头文件搜索顺序，特别是对 #include_next 的处理，从而导致 "limits.h" 找不到的编译错误。
            # -U_FORTIFY_SOURCE ...: 解决 glibc 版本安全检查问题。
            CFLAGS_EXTRA="--sysroot=/usr/riscv64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
            ;;
        aarch64)
            # 设置编译器和 sysroot
            export CC="aarch64-linux-gnu-gcc --sysroot=/usr/aarch64-linux-gnu"
            # --sysroot 会让编译器自动、正确地查找系统头文件。
            # 同样地，避免使用 -I 手动指定系统路径，以防破坏编译器的头文件搜索顺序。
            CFLAGS_EXTRA="--sysroot=/usr/aarch64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
            ;;
    esac

    # 在 make 命令中，将我们构造的 CFLAGS_EXTRA 添加进去
    # 我们使用 CFLAGS+="${CFLAGS_EXTRA}" 的语法，确保所有标志都被正确传递
    # 注意：这里的 ARCH 应该是 riscv64 而不是 riscv
    make -e all \
        ARCH=riscv64 \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}" \
        "CFLAGS+=${CFLAGS_EXTRA}" \
        MAKE='make -e'
}

deploy_artifacts() {
    echo "=== Deploying build artifacts ==="
    local dest_dir="${ROOTFS_DIR}/home/riscv64"
    local test_dest="${dest_dir}/test"
    # 创建目标目录
    sudo mkdir -p "${dest_dir}"
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

# ========================
# Main Execution Flow
# ========================
(
    cd "${WORKSPACE_ROOT}/platform/riscv64/qemu-plic/image/virtdisk"
    
    # Setup environment
    mount_rootfs
    # CI中代码已由 actions/checkout@v4 准备好，通常不需要再 clone
    # prepare_sources
    
    # Build process
    if ! build_hvisor_tool; then
        echo "ERROR: Build failed" >&2
        exit 1
    fi
    
    # Deployment
    deploy_artifacts

    # Cleanup
    echo "=== Unmounting rootfs ==="
    sudo umount "${ROOTFS_DIR}"
) || exit 1