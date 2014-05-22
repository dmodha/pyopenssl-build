#!/bin/bash

OPENSSL_VERSION=1.0.1g
PYTHON_VERSION=2.6.9
LIBFFI_VERSION=3.0.13

CLEAN_SSL=$1

set -e

# Figure out what directory this script is in
SCRIPT="$0"
if [[ $(readlink $SCRIPT) != "" ]]; then
    SCRIPT=$(dirname $SCRIPT)/$(readlink $SCRIPT)
fi
if [[ $0 = ${0%/*} ]]; then
    SCRIPT=$(pwd)/$0
fi
LINUX_DIR=$(cd ${SCRIPT%/*} && pwd -P)

if [[ $(uname -m) != 'i686' ]]; then
    echo "Unable to cross-compile Python and this machine is running the arch $(uname -m), not i686"
    exit 1
fi

DEPS_DIR="${LINUX_DIR}/deps"
BUILD_DIR="${LINUX_DIR}/py26-i686"
STAGING_DIR="$BUILD_DIR/staging"
BIN_DIR="$STAGING_DIR/bin"
OUT_DIR="$BUILD_DIR/../../out/py26_linux_x32"

export LDFLAGS="-Wl,-rpath='\$\$ORIGIN/' -Wl,-rpath=${STAGING_DIR}/lib -L${STAGING_DIR}/lib"
export CPPFLAGS="-I${STAGING_DIR}/include -I${STAGING_DIR}/include/openssl -I${STAGING_DIR}/lib/libffi-${LIBFFI_VERSION}/include/"

mkdir -p $DEPS_DIR
mkdir -p $BUILD_DIR
mkdir -p $STAGING_DIR
mkdir -p $OUT_DIR

LIBFFI_DIR="${DEPS_DIR}/libffi-$LIBFFI_VERSION"
LIBFFI_BUILD_DIR="${BUILD_DIR}/libffi-$LIBFFI_VERSION"

OPENSSL_DIR="${DEPS_DIR}/openssl-$OPENSSL_VERSION"
OPENSSL_BUILD_DIR="${BUILD_DIR}/openssl-$OPENSSL_VERSION"

PYTHON_DIR="${DEPS_DIR}/Python-$PYTHON_VERSION"
PYTHON_BUILD_DIR="${BUILD_DIR}/Python-$PYTHON_VERSION"

WGET_ERROR=0

download() {
    if (( ! $WGET_ERROR )); then
        # Ignore error with wget
        set +e
        wget "$1"
        # If wget is too old to support SNI
        if (( $? == 5 )); then
            WGET_ERROR=1
        fi
        set -e
    fi
    if (( $WGET_ERROR )); then
        curl -O "$1"
    fi
}

if [[ ! -e $OPENSSL_DIR ]]; then
    cd $DEPS_DIR
    download "http://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
    tar xvfz openssl-$OPENSSL_VERSION.tar.gz
    rm openssl-$OPENSSL_VERSION.tar.gz
    cd $LINUX_DIR
fi

if [[ ! -e $OPENSSL_BUILD_DIR ]] || [[ $CLEAN_SSL != "" ]]; then
    if [[ -e $OPENSSL_BUILD_DIR ]]; then
        rm -R $OPENSSL_BUILD_DIR
    fi
    cp -R $OPENSSL_DIR $BUILD_DIR

    cd $OPENSSL_BUILD_DIR

    patch -p0 < $LINUX_DIR/patch/patch-cms
    patch -p0 < $LINUX_DIR/patch/patch-smime
    patch -p0 < $LINUX_DIR/patch/patch-SSL_accept
    patch -p0 < $LINUX_DIR/patch/patch-SSL_clear
    patch -p0 < $LINUX_DIR/patch/patch-SSL_COMP_add_compression_method
    patch -p0 < $LINUX_DIR/patch/patch-SSL_connect
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_add_session
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_load_verify_locations
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_set_client_CA_list
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_set_session_id_context
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_set_ssl_version
    patch -p0 < $LINUX_DIR/patch/patch-SSL_CTX_use_psk_identity_hint
    patch -p0 < $LINUX_DIR/patch/patch-SSL_do_handshake
    patch -p0 < $LINUX_DIR/patch/patch-SSL_read
    patch -p0 < $LINUX_DIR/patch/patch-SSL_session_reused
    patch -p0 < $LINUX_DIR/patch/patch-SSL_set_fd
    patch -p0 < $LINUX_DIR/patch/patch-SSL_set_session
    patch -p0 < $LINUX_DIR/patch/patch-SSL_shutdown
    patch -p0 < $LINUX_DIR/patch/patch-SSL_write
    ./config shared no-md2 no-rc5 no-ssl2 --prefix=$STAGING_DIR -Wl,--version-script=openssl.ld -Wl,-Bsymbolic-functions -Wl,-rpath=XORIGIN/ -Wl,-rpath=${STAGING_DIR}/lib -fPIC
    echo 'OPENSSL_1.0.1G_PYTHON {
    global:
        *;
};
' > openssl.ld
    make depend
    make
    chrpath -r "\$ORIGIN/:${STAGING_DIR}/lib" libssl.so.1.0.0
    chrpath -r "\$ORIGIN/:${STAGING_DIR}/lib" libcrypto.so.1.0.0
    make install

    cd $LINUX_DIR
fi

if [[ ! -e $LIBFFI_DIR ]]; then
    cd $DEPS_DIR
    download "ftp://sourceware.org/pub/libffi/libffi-$LIBFFI_VERSION.tar.gz"
    tar xvfz libffi-$LIBFFI_VERSION.tar.gz
    rm libffi-$LIBFFI_VERSION.tar.gz
    cd $LINUX_DIR
fi

if [[ -e $LIBFFI_BUILD_DIR ]]; then
    rm -R $LIBFFI_BUILD_DIR
fi
cp -R $LIBFFI_DIR $BUILD_DIR

cd $LIBFFI_BUILD_DIR
./configure --disable-shared --prefix=${STAGING_DIR} CFLAGS=-fPIC
make
make install

cd $LINUX_DIR

if [[ ! -e $PYTHON_DIR ]]; then
    cd $DEPS_DIR
    download "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
    tar xvfz Python-$PYTHON_VERSION.tgz
    rm Python-$PYTHON_VERSION.tgz
    cd $LINUX_DIR
fi

if [[ -e $PYTHON_BUILD_DIR ]]; then
    rm -R $PYTHON_BUILD_DIR
fi
cp -R $PYTHON_DIR $BUILD_DIR

cd $PYTHON_BUILD_DIR

./configure --prefix=$STAGING_DIR
make
make install

cd $LINUX_DIR


cd $DEPS_DIR

if [[ ! -e ./get-pip.py ]]; then
    download "https://bootstrap.pypa.io/get-pip.py"
fi

$BIN_DIR/python2.6 ./get-pip.py

# Since this doesn't use make, we change the rpath to use a single $
export LDFLAGS="-Wl,-rpath='\$ORIGIN/' -Wl,-rpath=${STAGING_DIR}/lib -L${STAGING_DIR}/lib"

$BIN_DIR/pip2.6 install cryptography pyopenssl

rm -Rf $OUT_DIR/*

cp $STAGING_DIR/lib/libcrypto.so.1.0.0 $OUT_DIR/
cp $STAGING_DIR/lib/libssl.so.1.0.0 $OUT_DIR/
cp $STAGING_DIR/lib/python2.6/site-packages/six.py $OUT_DIR/
cp -R $STAGING_DIR/lib/python2.6/site-packages/OpenSSL $OUT_DIR/
cp -R $STAGING_DIR/lib/python2.6/site-packages/cryptography $OUT_DIR/
cp -R $STAGING_DIR/lib/python2.6/site-packages/cffi $OUT_DIR/
cp -R $STAGING_DIR/lib/python2.6/site-packages/pycparser $OUT_DIR/
cp $STAGING_DIR/lib/python2.6/site-packages/_cffi_backend.so $OUT_DIR/