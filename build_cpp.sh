```bash
#!/bin/bash

set -Eeuo pipefail

whisper_path="${1:?Usage: build_cpp.sh <whisper.cpp path> [target] [toolchain path]}"
targets="${2:-all}"
android_sdk_path="${3:-}"
unity_project="$PWD"
build_path="$whisper_path/build"

clean_build() {
  rm -rf "$build_path"
  mkdir -p "$build_path"
  cd "$build_path"
}

build_mac() {
  clean_build
  echo "Starting building for Mac (Metal)..."

  cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
    -DGGML_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    "$whisper_path"

  cmake --build "$build_path" --parallel 4

  echo "Build for Mac (Metal) complete!"

  target_path="$unity_project/Packages/com.whisper.unity/Plugins/MacOS"
  mkdir -p "$target_path"

  cp "$build_path/src/libwhisper.dylib" "$target_path/"

  find "$build_path/ggml/src" -type f -name '*.dylib' \
    -exec cp {} "$target_path/" \;

  for file in "$target_path"/*.dylib; do
    [ -f "$file" ] || continue
    install_name_tool -add_rpath @loader_path "$file" || true
  done

  echo "Build files copied to $target_path"
}

build_ios() {
  clean_build
  echo "Starting building for iOS..."

  cmake \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DGGML_METAL=ON \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_IOS_INSTALL_COMBINED=YES \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    "$whisper_path"

  cmake --build "$build_path" --parallel 4

  echo "Build for iOS complete!"

  target_path="$unity_project/Packages/com.whisper.unity/Plugins/iOS"
  mkdir -p "$target_path"

  cp "$build_path/src/libwhisper.a" "$target_path/"
  find "$build_path/ggml/src" -type f -name '*.a' \
    -exec cp {} "$target_path/" \;

  echo "Build files copied to $target_path"
}

build_android() {
  if [ -z "$android_sdk_path" ]; then
    echo "ERROR: Android CMake toolchain path was not provided."
    echo "Pass the path to android.toolchain.cmake as the third argument."
    exit 1
  fi

  if [ ! -f "$android_sdk_path" ]; then
    echo "ERROR: Android toolchain not found: $android_sdk_path"
    exit 1
  fi

  clean_build
  echo "Starting building for Android..."
  echo "Source: $whisper_path"
  echo "Build: $build_path"
  echo "Toolchain: $android_sdk_path"

  cmake \
    -S "$whisper_path" \
    -B "$build_path" \
    -DCMAKE_TOOLCHAIN_FILE="$android_sdk_path" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DGGML_OPENMP=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build "$build_path" --parallel 4

  echo "Checking generated Android libraries..."

  required_libraries=(
    "$build_path/ggml/src/libggml-base.a"
    "$build_path/ggml/src/libggml-cpu.a"
    "$build_path/ggml/src/libggml.a"
    "$build_path/src/libwhisper.a"
  )

  for lib in "${required_libraries[@]}"; do
    if [ ! -s "$lib" ]; then
      echo "ERROR: Required library missing or empty: $lib"
      echo "Contents of build directory:"
      find "$build_path" -type f \( -name '*.a' -o -name '*.so' \) -print
      exit 1
    fi
    ls -lh "$lib"
  done

  target_path="$unity_project/Packages/com.whisper.unity/Plugins/Android"
  mkdir -p "$target_path"

  # Remove old archives only after all new archives have been verified.
  rm -f "$target_path"/*.a

  for lib in "${required_libraries[@]}"; do
    cp "$lib" "$target_path/"
  done

  echo "Android libraries copied successfully:"
  ls -lh "$target_path"

  for lib in libggml-base.a libggml-cpu.a libggml.a libwhisper.a; do
    if [ ! -s "$target_path/$lib" ]; then
      echo "ERROR: Library missing after copy: $target_path/$lib"
      exit 1
    fi
  done

  echo "Build for Android complete!"
}

case "$targets" in
  all)
    build_mac
    build_ios
    build_android
    ;;
  mac)
    build_mac
    ;;
  ios)
    build_ios
    ;;
  android)
    build_android
    ;;
  *)
    echo "ERROR: Unknown target: $targets"
    echo "Valid targets: all, mac, ios, android"
    exit 1
    ;;
esac
```
