#!/bin/bash
set -e

# Generate header with secrets pulled from ~/.config/koreader/secrets.txt
generate_secrets() {
    local CONFIG_FILE="$HOME/.config/koreader/secrets.txt"
    local OUT_FILE="src/generated_secrets.h"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "\e[31mError: Secrets file not found at $CONFIG_FILE\e[0m" >&2
        exit 1
    fi

    # Expect lines in the form:
    # "instapaper_oauth_consumer_key" = "YOURKEY"
    # "instapaper_oauth_consumer_secret" = "YOURSECRET"

    local CK=$(grep -E '"instapaper_ouath_consumer_key"' "$CONFIG_FILE" | \
        sed -E 's/.*"instapaper_ouath_consumer_key"[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    local CS=$(grep -E '"instapaper_oauth_consumer_secret"' "$CONFIG_FILE" | \
        sed -E 's/.*"instapaper_oauth_consumer_secret"[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')

    if [ -z "$CK" ] || [ -z "$CS" ]; then
        echo "\e[31mError: instapaper_oauth_consumer_key or instapaper_oauth_consumer_secret missing in $CONFIG_FILE\e[0m" >&2
        exit 1
    fi

    cat > "$OUT_FILE" <<EOF
#pragma once
#define INSTAPAPER_CONSUMER_KEY "$CK"
#define INSTAPAPER_CONSUMER_SECRET "$CS"
EOF
}

# Call once at the start
generate_secrets

# Cleanup function to remove generated files
cleanup() {
    rm -f src/generated_secrets.h
}

# Set up trap to cleanup on exit
trap cleanup EXIT

# Helper to rename built library with target suffix
rename_lib() {
    local suffix="$1"
    if [ -f instapapersecrets.so ]; then
        mv -f instapapersecrets.so "instapapersecrets_${suffix}.so"
    fi
}

# Usage: ./build_in_docker.sh [target]
# Example: ./build_in_docker.sh dev     # Local development build
# Example: ./build_in_docker.sh kobo    # Release ARM build via Docker
# Future: ./build_in_docker.sh kindle   # Future target

TARGET=${1:-dev}
IMAGE=koreader/kokobo:latest
WORKDIR=/workspace
KOREADER_DIR=/koreader

# You can add more targets and toolchain logic here as needed
case "$TARGET" in
    dev)
        echo "Building for development (local architecture)"
        make clean
        make CC=g++ CFLAGS="-fPIC -O2 -Wall -g" LDFLAGS="-shared"
        ;;
    kobo)
        # Set up cross-compilation environment and build
        CMD="cd $KOREADER_DIR && ./kodev fetch-thirdparty && export PATH=/usr/local/x-tools/arm-kobo-linux-gnueabihf/bin:\$PATH && cd $WORKDIR && make clean && make"
        echo "Building for target: $TARGET using Docker image: $IMAGE"
        echo "Mounting KOReader repo from ~/dev/koreader to set up cross-compilation environment"
        docker run --rm -it \
            -v "$(pwd):$WORKDIR" \
            -v "$HOME/dev/koreader:$KOREADER_DIR" \
            -w "$WORKDIR" \
            $IMAGE bash -c "$CMD"
        rename_lib "$TARGET"
        ;;
    kindlepw2)
        # Switch to the Kindle-specific Docker image
        IMAGE=koreader/kokindle:latest

        # The kindlepw2 configuration uses the arm-kindlepw2-linux-gnueabi toolchain
        TOOLCHAIN_PATH=/usr/local/x-tools/arm-kindlepw2-linux-gnueabi/bin
        TOOLCHAIN_PREFIX=arm-kindlepw2-linux-gnueabi
        # Build command
        CMD="cd $KOREADER_DIR && ./kodev fetch-thirdparty && export PATH=$TOOLCHAIN_PATH:\$PATH && cd $WORKDIR && make clean && make CC=${TOOLCHAIN_PREFIX}-c++"

        echo "Building for target: $TARGET (kindlepw2) using Docker image: $IMAGE"
        echo "Mounting KOReader repo from ~/dev/koreader to set up cross-compilation environment"

        docker run --rm -it \
            -v "$(pwd):$WORKDIR" \
            -v "$HOME/dev/koreader:$KOREADER_DIR" \
            -w "$WORKDIR" \
            $IMAGE bash -c "$CMD"
        rename_lib "$TARGET"
        ;;
    kindlehf)
        IMAGE=koreader/kokindle:latest
        TOOLCHAIN_PATH=/usr/local/x-tools/arm-kindle5-linux-gnueabi/bin
        TOOLCHAIN_PREFIX=arm-kindle5-linux-gnueabi
        CMD="cd $KOREADER_DIR && ./kodev fetch-thirdparty && export PATH=$TOOLCHAIN_PATH:\$PATH && cd $WORKDIR && make clean && make CC=${TOOLCHAIN_PREFIX}-c++"

        echo "Building for target: $TARGET (kindle hard-float) using Docker image: $IMAGE"
        docker run --rm -it \
            -v "$(pwd):$WORKDIR" \
            -v "$HOME/dev/koreader:$KOREADER_DIR" \
            -w "$WORKDIR" \
            $IMAGE bash -c "$CMD"
        rename_lib "$TARGET"
        ;;

    kindle)
        IMAGE=koreader/kokindle:latest
        TOOLCHAIN_PATH=/usr/local/x-tools/arm-kindle-linux-gnueabi/bin
        TOOLCHAIN_PREFIX=arm-kindle-linux-gnueabi
        CMD="cd $KOREADER_DIR && ./kodev fetch-thirdparty && export PATH=$TOOLCHAIN_PATH:\$PATH && cd $WORKDIR && make clean && make CC=${TOOLCHAIN_PREFIX}-c++"

        echo "Building for target: $TARGET (generic Kindle) using Docker image: $IMAGE"
        docker run --rm -it \
            -v "$(pwd):$WORKDIR" \
            -v "$HOME/dev/koreader:$KOREADER_DIR" \
            -w "$WORKDIR" \
            $IMAGE bash -c "$CMD"
        rename_lib "$TARGET"
        ;;

    kindle-legacy)
        IMAGE=koreader/kokindle:latest
        TOOLCHAIN_PATH=/usr/local/x-tools/arm-kindle-linux-gnueabi/bin
        TOOLCHAIN_PREFIX=arm-kindle-linux-gnueabi
        CMD="cd $KOREADER_DIR && ./kodev fetch-thirdparty && export PATH=$TOOLCHAIN_PATH:\$PATH && cd $WORKDIR && make clean && make CC=${TOOLCHAIN_PREFIX}-c++"

        echo "Building for target: $TARGET (legacy Kindle) using Docker image: $IMAGE"
        docker run --rm -it \
            -v "$(pwd):$WORKDIR" \
            -v "$HOME/dev/koreader:$KOREADER_DIR" \
            -w "$WORKDIR" \
            $IMAGE bash -c "$CMD"
        rename_lib "$TARGET"
        ;;

    all)
        # Build all non-development targets sequentially
        for t in kobo kindlepw2 kindlehf kindle kindle-legacy; do
            "$0" "$t"
        done
        ;;
    # Add more targets here
    *)
        echo "Unknown target: $TARGET"
        echo "Available targets:"
        echo "  dev   - Local development build (current architecture)"
        echo "  kobo  - Release ARM build via Docker"
        echo "  kindlepw2 - Release ARM build for Kindle PW2 via Docker"
        echo "  kindlehf - Release ARM build for newer hard-float Kindles via Docker"
        echo "  kindle  - Generic Kindle build via Docker"
        echo "  kindle-legacy - Older Kindle models build via Docker"
        echo "  all   - Build all non-development targets"
        exit 1
        ;;
esac 