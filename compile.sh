#!/bin/bash

# To build your desired environment:
# # heroku run bash
# # ./compile.sh 7.1.32

if [ -z "$1" ]; then
    SWI_BRANCH="master";
else
    SWI_BRANCH="V$1"
    SWI_VERSION="$1"
fi


set -e
BIN_DIR=$(cd $(dirname $0); pwd) # absolute path
bpdir=$(cd $(dirname $(dirname $0)); pwd)
mkdir -p build cache .local
build=$(cd "build/" && pwd)
test -z ${build} && exit
cache=$(cd "cache/" && pwd)
test -z ${cache} && exit
PROFILE=${HOME}/.profile.d

# If we have a copy of the build environment already, just use that!
echo "------> Compiling Prolog"
(
    # First though, do we have unixodbc?
    echo "------> unixODBC"
    (
        echo "------> Fetching unixODBC"
        mkdir -p ${build}/unixodbc-build
        cd ${build}/unixodbc-build
        curl ftp://ftp.unixodbc.org/pub/unixODBC/unixODBC-2.3.4.tar.gz -s -o - | tar -zx -f -
        cd unixODBC-2.3.4
        echo "------> Compiling unixODBC"
        ./configure --prefix=/app/.local > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        rm -rf ${build}/unixodbc-build
    )
    # Then: Do we have gmp?
    echo "------> gmp"
    (
        echo "------> Fetching gmp"
        mkdir -p ${build}/gmp-build
        cd ${build}/gmp-build
        curl https://ftp.gnu.org/gnu/gmp/gmp-6.0.0a.tar.bz2 -s -o - | tar -jx -f -
        cd gmp-6.0.0
        echo "------> Compiling gmp"
        ./configure --prefix=/app/.local > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        rm -rf ${build}/gmp-build
    )
    # Next: Do we have psqlodbc?
    echo "------> psqlodbc"
    (
        echo "------> Fetching psqlodbc"
        mkdir -p ${build}/psqlodbc-build
        cd ${build}/psqlodbc-build 
        curl http://ftp.postgresql.org/pub/odbc/versions/src/psqlodbc-09.01.0200.tar.gz -s -o - | tar -zx -f -
        cd psqlodbc-09.01.0200
        echo "------> Compiling psqlodbc"
        LD_LIBRARY_PATH=/app/.local/lib ./configure --prefix=/app/.local --with-unixodbc=/app/.local --without-libpq > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        rm -rf ${build}/psqlodbc-build
    )

    # Next: Do we have libarchive?
    echo "------> libarchive"
    (
        echo "------> Fetching libarchive"
        mkdir -p ${build}/libarchive-build
        cd ${build}/libarchive-build
        curl http://www.libarchive.org/downloads/libarchive-3.2.0.tar.gz -s -o - | tar -zx -f -
        cd libarchive-3.2.0
        echo "------> Compiling libarchive"
        ./configure --prefix=/app/.local > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        rm -rf ${build}/libarchive-build
    )

    # Finally: Prolog
    echo "-----> Building prolog"
    (
        set -e
        # We MUST do this or git will go bezerk when we try to do anything to the checked-out SWI repository
        unset GIT_DIR

        # Build Prolog in ${build}/swipl-build, and install to /app/.swipl then compress
        # /app/.swipl to ${cache}/swipl-${ID}.tgz
        rm -rf ${build}/swipl-build
        mkdir -p ${build}/swipl-build
        cd ${build}/swipl-build
        echo "------> Fetching SWI Prolog from git"
        if [ ${SWI_BRANCH} == "master" ] ; then
            git clone https://github.com/SWI-Prolog/swipl-devel.git > /dev/null 2>&1
            cd swipl-devel
            ID=$(cat VERSION)
        else
            git clone --branch ${ID} https://github.com/SWI-Prolog/swipl-devel.git > /dev/null 2>&1
            cd swipl-devel
            ID=${SWI_VERSION}
        fi
        echo "------> Building SWI Prolog ${ID} in ${build}/swipl-build"
        # First apply a very small patch so we can compile on Cedar. This seems to be harmless. Hopefully.
        sed -i -e 's@2.66@2.65@g' src/configure.in
        # Prepare the build
        ./prepare --yes --all --man > /dev/null 2>&1
        # Configure and build it
        export LD_RUN_PATH=/app/.local/lib
        export LDFLAGS="$LDFLAGS -LLIBDIR -Wl,-rpath=/app/.local/lib -L/app/.local/lib -Wl,-rpath=/app/.local/lib"
        export CFLAGS="$CFLAGS -I/app/.local/include"
        ./configure --with-world --with-odbc=/app/.local --prefix=/app/.local> /dev/null 2>&1
        make > /dev/null 2>&1
        echo "------> Installing SWI Prolog ${ID}"
        make install > /dev/null 2>&1
        cd /app
        # Now clean up
        rm -rf ${build}/swipl-build
        echo "------> Installed SWI Prolog ${ID}"
        tar -cjf ${BIN_DIR}/env-${ID}.tar.bz2 .local
        rm -rf .local
        echo "Environment is in ${BIN_DIR}/env-${ID}.tar.bz2"

    )
)

