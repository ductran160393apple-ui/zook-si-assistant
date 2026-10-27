# Build lõi Rust + app Android trong Docker (linux/amd64):
# Rust, cargo-ndk, Android SDK 35, NDK r27c, Gradle.
# Không cài toolchain lên máy chủ; cache (kể cả debug keystore để APK
# giữ cùng chữ ký) nằm trong Docker volume.
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_VERSION=r27c

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl unzip openjdk-17-jdk-headless git build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain 1.94.0 --target aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install cargo-ndk

RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools && \
    curl -o /tmp/cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip -q /tmp/cmdtools.zip -d $ANDROID_SDK_ROOT/cmdline-tools && \
    mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest && \
    rm /tmp/cmdtools.zip && \
    curl -sSL -o /tmp/gradle.zip https://services.gradle.org/distributions/gradle-8.10-bin.zip && \
    unzip -q /tmp/gradle.zip -d /opt && rm /tmp/gradle.zip && ln -s /opt/gradle-8.10/bin/gradle /usr/local/bin/gradle
ENV PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:${PATH}"
RUN yes | sdkmanager --licenses >/dev/null && \
    sdkmanager "platform-tools" "platforms;android-35" "ndk;27.0.12077973" "build-tools;35.0.0"

WORKDIR /work
# Ví dụ (cache cargo/gradle nằm trong volume để build lại nhanh):
#   docker build -t aiassist-builder .
#   docker run --rm -v "$PWD:/work" -v aiassist-cargo:/root/.cargo \
#     -v aiassist-gradle:/root/.gradle \
#     -e ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.0.12077973 aiassist-builder \
#     bash -c 'cd /work/android && gradle assembleDebug'
# Task buildRust (preBuild) tự chạy cargo ndk cho 3 ABI rồi chép .so vào jniLibs.
