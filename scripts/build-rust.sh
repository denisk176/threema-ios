#!/usr/bin/env bash

if [ "$#" -lt 2 ]
then
    echo "Usage:"
    echo "Args: $*"
    echo "path/to/build-scripts/build-rust.sh <CARGO_DIR> <FFI_TARGET>"
    exit 1
fi

# cargo dir
CARGO_DIR=$1
# what to pass to cargo build -p, e.g. saltyrtc-task-relayed-data-ffi
FFI_TARGET=$2

# We need this specific version due to https://github.com/saltyrtc/saltyrtc-task-relayed-data-rs
# using it.
TOOLCHAIN_VERSION=1.63

set -euvx

# Install toolchain & targets.
# The pinned toolchain is installed and selected through mise (`mise exec rust@<version>`),
# overriding the mise-managed default rust version just for these commands.

mise install rust@$TOOLCHAIN_VERSION
mise exec rust@$TOOLCHAIN_VERSION -- rustup target add aarch64-apple-ios aarch64-apple-ios-sim

# Build

cd "$CARGO_DIR"

mise exec rust@$TOOLCHAIN_VERSION -- cargo build --locked -p $FFI_TARGET --lib --release --target aarch64-apple-ios
mise exec rust@$TOOLCHAIN_VERSION -- cargo build --locked -p $FFI_TARGET --lib --release --target aarch64-apple-ios-sim
