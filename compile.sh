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
mkdir -p build cache
build=$(cd "build/" && pwd)
test -z ${build} && exit
cache=$(cd "cache/" && pwd)
test -z ${cache} && exit
PROFILE=${HOME}/.profile.d

# If we have a copy of the build environment already, just use that!
echo "------> Compiling Prolog"
(
    # Testing: Recompile all
    # rm ${cache}/*.tgz

    # First though, do we have unixodbc?
    echo "------> Checking for unixODBC"
    (
        test -f ${cache}/unixodbc.tgz && exit
        echo "------> Fetching unixODBC"
        mkdir -p ${build}/unixodbc-build
        cd ${build}/unixodbc-build
        curl ftp://ftp.unixodbc.org/pub/unixODBC/unixODBC-2.3.4.tar.gz -s -o - | tar -zx -f -
        cd unixODBC-2.3.4
        echo "------> Compiling unixODBC"
        ./configure --prefix=/app/.odbc > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        tar -czf ${cache}/unixodbc.tgz .odbc
        rm -rf ${build}/unixodbc-build
        rm -rf /app/.odbc
    )
    echo "------> Unpacking unixODBC"
    cd /app
    tar -xzf ${cache}/unixodbc.tgz

    # Then: Do we have gmp?
    echo "------> Checking for gmp"
    (
        test -f ${cache}/gmp.tgz && exit
        echo "------> Fetching gmp"
        mkdir -p ${build}/gmp-build
        cd ${build}/gmp-build
        curl https://ftp.gnu.org/gnu/gmp/gmp-6.0.0a.tar.bz2 -s -o - | tar -jx -f -
        cd gmp-6.0.0
        echo "------> Compiling gmp"
        ./configure --prefix=/app/.gmp > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        tar -czf ${cache}/gmp.tgz .gmp
        rm -rf ${build}/gmp-build
        rm -rf /app/.gmp
    )
    echo "------> Unpacking gmp"
    cd /app
    tar -zxf ${cache}/gmp.tgz

    # Next: Do we have psqlodbc?
    echo "------> Checking for psqlodbc"
    (
        test -f ${cache}/psqlodbc.tgz && exit
        echo "------> Fetching psqlodbc"
        mkdir -p ${build}/psqlodbc-build
        cd ${build}/psqlodbc-build 
        curl http://ftp.postgresql.org/pub/odbc/versions/src/psqlodbc-09.01.0200.tar.gz -s -o - | tar -zx -f -
        cd psqlodbc-09.01.0200
        echo "------> Compiling psqlodbc"
        LD_LIBRARY_PATH=/app/.odbc/lib ./configure --prefix=/app/.psqlodbc --with-unixodbc=/app/.odbc --without-libpq > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        tar -czf ${cache}/psqlodbc.tgz .psqlodbc
        rm -rf ${build}/psqlodbc-build
        rm -rf /app/.psqlodbc
    )
    echo "------> Unpacking psqlodbc"
    cd /app
    tar -xzf ${cache}/psqlodbc.tgz

    # Next: Do we have libarchive?
    echo "------> Checking for libarchive"
    (
        test -f ${cache}/libarchive.tgz && exit
        echo "------> Fetching libarchive"
        mkdir -p ${build}/libarchive-build
        cd ${build}/libarchive-build
        curl http://www.libarchive.org/downloads/libarchive-3.2.0.tar.gz -s -o - | tar -zx -f -
        cd libarchive-3.2.0
        echo "------> Compiling libarchive"
        ./configure --prefix=/app/.libarchive > /dev/null 2>&1
        make > /dev/null 2>&1
        make install > /dev/null 2>&1
        cd /app
        tar -czf ${cache}/libarchive.tgz .libarchive
        rm -rf ${build}/libarchive-build
        rm -rf /app/.libarchive
    )
    echo "------> Unpacking libarchive"
    cd /app
    tar -xzf ${cache}/libarchive.tgz

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
        if [ ${SWI_BRANCH} == "master"] ; then
            git clone https://github.com/SWI-Prolog/swipl-devel.git > /dev/null 2>&1
            ID=$(cat VERSION)
        else
            git clone --branch ${ID} https://github.com/SWI-Prolog/swipl-devel.git > /dev/null 2>&1
            ID=${SWI_VERSION}
        fi
        cd swipl-devel
        echo "------> Switching to version ${ID}"
        git checkout ${ID} > /dev/null 2>&1
        echo "------> Building SWI Prolog ${ID} in ${build}/swipl-build"
        # First apply a very small patch so we can compile on Cedar. This seems to be harmless. Hopefully.
        sed -i -e 's@2.66@2.65@g' src/configure.in
        # Prepare the build
        ./prepare --yes --all --man > /dev/null 2>&1
        # Configure and build it
        export LD_RUN_PATH=/app/.odbc/lib
        export LDFLAGS="$LDFLAGS -LLIBDIR -Wl,-rpath=/app/.odbc/lib -L/app/.gmp/lib -Wl,-rpath=/app/.gmp/lib"
        export CFLAGS="$CFLAGS -I/app/.gmp/include"
        ./configure --with-world --with-odbc=/app/.odbc --prefix=/app/.swipl> /dev/null 2>&1
        make > /dev/null 2>&1
        echo "------> Installing SWI Prolog ${ID}"
        make install > /dev/null 2>&1
        echo "------> Preparing CQL"
        (
            test -f packages/cql && exit
            cd packages
            git clone https://github.com/SWI-Prolog/packages-cql.git > /dev/null 2>&1
            cd packages-cql
            make install > /dev/null 2>&1
        )
        cd /app
        tar -czf ${cache}/swipl-${ID}.tgz .swipl
        # Now clean up
        rm -rf ${build}/swipl-build
        rm -rf /app/.swipl
        echo "------> Installed SWI Prolog ${ID}"
    )

    cd /app
    tar -xzf ${cache}/swipl-${ID}.tgz
    tar -cjf ${BIN_DIR}/env-${ID}.tar.bz2 /app

    echo "Environment is in ${BIN_DIR}/env-${ID}.tar.bz2"

)

