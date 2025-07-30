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
    if [ ! -d "linux_v6.10-rc1" ]; then
        git clone https://github.com/CHonghaohao/linux_v6.10-rc1.git || return 1
    fi
    if [ ! -d "hvisor-tool" ]; then
        git clone https://github.com/syswonder/hvisor-tool.git || return 1
    fi
}

# ... 在 riscv64 的脚本中 ...

build_hvisor_tool() {
    echo "=== Building hvisor components ==="
    cd "${HVISOR_TOOL_DIR}"

    # 【关键修正：釜底抽薪】
    # 对 riscv64 也进行同样的手术，注释掉其 Makefile 中污染环境的 CFLAGS。
    echo "--- Patching hvisor-tool/tools/Makefile to prevent environment pollution ---"
    sed -i 's/^\(CFLAGS += -I\/usr\/riscv64-linux-gnu\/include.*\)/# \1/' tools/Makefile
    echo "--- Patching complete. Displaying patched file content: ---"
    cat tools/Makefile
    echo "--- End of patched file content ---"


    local MAKE_ARCH=""

    case "${ARCH}" in
        riscv64)
            export CC='riscv64-linux-gnu-gcc --sysroot=/usr/riscv64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0'
            MAKE_ARCH="riscv"
            ;;
        aarch64)
            export CC='aarch64-linux-gnu-gcc --sysroot=/usr/aarch64-linux-gnu -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0'
            MAKE_ARCH="arm64"
            ;;
    esac

    # 双重保险
    make -e all \
        ARCH=${MAKE_ARCH} \
        LOG=LOG_INFO \
        KDIR="${LINUX_KERNEL_DIR}" \
        CFLAGS="" \
        MAKE='make -e'
}

deploy_artifacts() {
    # ... 此函数内容无需修改 ...
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
    prepare_sources
    if [ "$SKIP_BUILD" != "true" ]; then
      echo "--- Build step is enabled. Starting build... ---"
      if ! build_hvisor_tool; then
          echo "ERROR: Build failed" >&2
          exit 1
      fi
    else
      echo "--- SKIP_BUILD is true. Skipping build step. ---"
    fi
    deploy_artifacts
    echo "=== Unmounting rootfs ==="
    sudo umount "${ROOTFS_DIR}"
) || exit 1