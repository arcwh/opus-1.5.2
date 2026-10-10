#!/bin/bash

set -e

# Path to your NDK
NDK=/Users/anathan/Documents/android-ndk-r28c
API=21

# Output so file name
OUTPUT_SO_NAME="librtk-audio-toolbox.so"

# Root directory of opus source
OPUS_SRC_DIR=$(pwd)

# Output directory for compiled libraries
OUTPUT_DIR=$OPUS_SRC_DIR/android/build

# Architectures to build
ARCHS=("armeabi-v7a" "arm64-v8a")

# Toolchain path
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/darwin-x86_64

build_opus() {
    ARCH=$1
    echo "------------------"
    echo "Building for $ARCH"
    echo "------------------"

    case $ARCH in
        armeabi-v7a)
            TARGET=armv7a-linux-androideabi
            HOST=arm-linux-androideabi
            CC=$TOOLCHAIN/bin/${TARGET}${API}-clang
            ;;
        arm64-v8a)
            TARGET=aarch64-linux-android
            HOST=aarch64-linux-android
            CC=$TOOLCHAIN/bin/${TARGET}${API}-clang
            ;;
        *)
            echo "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    INSTALL_DIR=$OUTPUT_DIR/$ARCH
    mkdir -p "$INSTALL_DIR"

    # Clean previous build artifacts
    make distclean || true

    # Configure and build libopus.a with position independent code
    ./configure \
        --host=$HOST \
        --disable-shared \
        --enable-static \
        --with-pic \
        CC=$CC \
        CFLAGS="-fPIC" \
        --prefix=$INSTALL_DIR

    make -j$(sysctl -n hw.ncpu)
    make install

    create_shared_library $ARCH $TARGET $CC $INSTALL_DIR
}

create_shared_library() {
    ARCH=$1
    TARGET=$2
    CC=$3
    INSTALL_DIR=$4

    echo "Creating shared library for $ARCH..."

    # Find the correct builtins runtime library
    case $ARCH in
      armeabi-v7a)
        BUILTINS_PATH=$(find "$TOOLCHAIN/lib/clang" -name "libclang_rt.builtins-arm-android.a" | head -n 1)
        ;;
      arm64-v8a)
        BUILTINS_PATH=$(find "$TOOLCHAIN/lib/clang" -name "libclang_rt.builtins-aarch64-android.a" | head -n 1)
        ;;
      x86_64)
        BUILTINS_PATH=$(find "$TOOLCHAIN/lib/clang" -name "libclang_rt.builtins-x86_64-android.a" | head -n 1)
        ;;
      *)
        echo "Unsupported ARCH: $ARCH"
        exit 1
        ;;
    esac

    if [ ! -f "$BUILTINS_PATH" ]; then
      echo "ERROR: Cannot find libclang_rt.builtins for ARCH $ARCH"
      exit 1
    fi

    echo "Linking static libs into $OUTPUT_SO_NAME"
    echo "Using builtins: $BUILTINS_PATH"

    # Link into shared library
    $CC \
      -fPIC \
      -shared \
      -nostdlib \
      -Wl,-Bsymbolic \
      -Wl,--no-undefined \
      -Wl,--whole-archive \
      $INSTALL_DIR/lib/libopus.a \
      -Wl,--no-whole-archive \
      -Wl,-soname=$OUTPUT_SO_NAME \
      -lc -lm -lz -llog -landroid -ldl \
      "$BUILTINS_PATH" \
      -o $INSTALL_DIR/lib/$OUTPUT_SO_NAME

    echo "Shared library created at: $INSTALL_DIR/lib/$OUTPUT_SO_NAME"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build for each architecture
for ARCH in "${ARCHS[@]}"; do
    build_opus $ARCH
done

echo "All builds completed. Shared libraries are in: $OUTPUT_DIR"