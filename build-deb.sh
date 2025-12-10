#!/bin/bash
set -e

# Configuration
VERSION="2.6.23"
PACKAGE_VERSION="2.6.23-flipboard"
ARCH="arm64"
PACKAGE_NAME="haproxy_${PACKAGE_VERSION}_${ARCH}.deb"

echo "Building HAProxy ${PACKAGE_VERSION} for ${ARCH}..."

# Create build directory structure
BUILD_DIR="builds/haproxy-build"
PKG_DIR="${BUILD_DIR}/debian-pkg"
OUTPUT_DIR="builds"

mkdir -p ${OUTPUT_DIR}
rm -rf ${BUILD_DIR}
mkdir -p ${PKG_DIR}/{DEBIAN,usr/sbin}

# Install build dependencies and build HAProxy inside the container
docker run --rm --platform linux/arm64 \
  -v $(pwd):/workspace \
  -w /workspace \
  ubuntu:22.04 /bin/bash -c '
set -e

# Install dependencies
apt-get update
apt-get install -y \
  build-essential \
  libpcre3-dev \
  libssl-dev \
  zlib1g-dev \
  libsystemd-dev \
  liblua5.3-dev \
  ca-certificates

echo "Building HAProxy..."

# Build HAProxy
make clean || true
make -j$(nproc) TARGET=linux-glibc \
  USE_PCRE=1 \
  USE_OPENSSL=1 \
  USE_ZLIB=1 \
  USE_SYSTEMD=1 \
  USE_LUA=1 \
  USE_PROMEX=1 \
  USE_THREAD=1

echo "HAProxy build complete"

# Copy binary to build directory
cp haproxy '${PKG_DIR}/usr/sbin/'
chmod 755 '${PKG_DIR}/usr/sbin/haproxy'

echo "Binary copied to package directory"
'

# Create control file
cat > ${PKG_DIR}/DEBIAN/control << EOF
Package: haproxy
Version: ${PACKAGE_VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Depends: libc6, libpcre3, libssl3 | libssl1.1, zlib1g, libsystemd0, liblua5.3-0
Maintainer: Flipboard OPS <ops@flipboard.com>
Description: Fast and reliable load balancing reverse proxy
 HAProxy is a TCP/HTTP reverse proxy which is particularly suited for high
 availability environments. It features connection persistence through HTTP
 cookies, load balancing, header addition, modification, deletion both ways.
 It has request blocking capabilities and provides interface to display server
 status.
 .
 This is a Flipboard customized build of HAProxy ${VERSION}.
EOF

# Set correct permissions
find ${PKG_DIR} -type d -exec chmod 755 {} \;

# Build the package inside Docker (since dpkg-deb isn't available on macOS)
echo "Building Debian package..."
docker run --rm --platform linux/arm64 \
  -v $(pwd):/workspace \
  -w /workspace \
  ubuntu:22.04 /bin/bash -c "
    dpkg-deb --build ${PKG_DIR} ${PACKAGE_NAME}
    dpkg-deb --info ${PACKAGE_NAME}
    echo ''
    echo 'Package contents:'
    dpkg-deb --contents ${PACKAGE_NAME}
  "

echo ""
echo "Package built successfully: ${PACKAGE_NAME}"

mv ${PACKAGE_NAME} ${OUTPUT_DIR}/${PACKAGE_NAME}
echo "Moved to ${OUTPUT_DIR}/${PACKAGE_NAME}"

echo ""
echo "To upload to S3, run:"
# loop for jammy and noble to echo both paths
for release in jammy noble; do
  echo "aws s3 cp ${OUTPUT_DIR}/${PACKAGE_NAME} s3://flipboard.prod.external/haproxy/${release}/${PACKAGE_NAME}"
done