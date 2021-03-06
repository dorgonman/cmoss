#!/bin/sh
set -e

# Copyright (c) 2011, Mevan Samaratunga
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * The name of Mevan Samaratunga may not be used to endorse or
#       promote products derived from this software without specific prior
#       written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


BOOST_SOURCE_NAME=boost_${BOOST_VERSION//./_}
BOOST_DOWNLOAD_FILE_SURFIX=".tar.bz2"
# Download source
if [ ! -e "${BOOST_SOURCE_NAME}${BOOST_DOWNLOAD_FILE_SURFIX}" ]
then
   curl $PROXY -O -L "http://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION}/${BOOST_SOURCE_NAME}${BOOST_DOWNLOAD_FILE_SURFIX}"
fi

# Build

#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#    BOOST_VERSION:     version number of the boost library (e.g. 1_41_0)
#    SDK_VER: iPhone SDK version (e.g. 3.0)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================


: ${EXTRA_CPPFLAGS:="-Os -DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS"}

# The EXTRA_CPPFLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

: ${TARBALLDIR:=`pwd`}

BOOST_TARBALL=$TARBALLDIR/${BOOST_SOURCE_NAME}${BOOST_DOWNLOAD_FILE_SURFIX}

#===============================================================================

DEV_DIR=${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/usr/bin/

#===============================================================================

JAM_FILE=$ROOTDIR/user-config.jam


echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_TARBALL:     $BOOST_TARBALL"
echo "SDK_VER: $SDK_VER"
echo "JAM_FILE: $JAM_FILE"
# boost needs its own versions of some values
if [ "${PLATFORM}" == "iPhoneSimulator" ]
then
    BOOST_PLAT="iphonesim"
else
    BOOST_PLAT="iphone"
fi

#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "    ================================================================="
    echo "    Done"
    echo
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...
    rm -rf "$BOOST_SOURCE_NAME"  || true
    doneSection
}

#===============================================================================
unpackBoost()
{
    echo Unpacking boost into $BOOST_SOURCE_NAME...

    rm -rfv "$BOOST_SOURCE_NAME"  || true

    tar zxf $BOOST_TARBALL
    [ -d $BOOST_SOURCE_NAME ] && echo "    ...unpacked as $BOOST_SOURCE_NAME"

    cp -rf  ${TOPDIR}/patches/* ${TMPDIR}/
    cd $BOOST_SOURCE_NAME

    doneSection
}

#===============================================================================

writeBjamUserConfig()
{
    # You need to do this to point bjam at the right compiler
    # ONLY SEEMS TO WORK IN HOME DIR GRR
    echo Writing usr-config

    cat >> ${JAM_FILE} <<EOF
using darwin : ${SDK_VER}~iphone
: ${CXX} -arch ${ARCH} $EXTRA_CPPFLAGS "-isysroot ${BUILD_SDKROOT}" -I${BUILD_SDKROOT}/usr/include/
: <striper> <root>${BUILD_DEVROOT}
: <architecture>${ARCHITECTURE} <target-os>iphone
;

EOF
    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp ${DEVELOPER}/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h .
}

#===============================================================================

bootstrapBoost()
{
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    doneSection
}

#===============================================================================

buildBoostForiPhoneOS()
{   
    echo rootDir: $ROOTDIR
    
    #cat ~./user-config.jam 
    #./bjam --prefix="$ROOTDIR" toolset=darwin-${SDK_VER}~${PLATFORM} \
    # architecture=${ARCHITECTURE} target-os=iphone macosx-version=iPhoneOS-${SDK_VER} define=_LITTLE_ENDIAN link=static install
    #./bjam --prefix="$ROOTDIR" toolset=darwin architecture=$BOOST_ARCH target-os=iphone macosx-version=${BOOST_PLAT}-${SDK_VER} define=_LITTLE_ENDIAN link=static install

    ./b2 --prefix=$ROOTDIR -sBOOST_BUILD_USER_CONFIG=$JAM_FILE \
    --toolset=darwin-${SDK_VER}~iphone cxxflags="-std=c++11 -stdlib=libc++" \
     variant=release linkflags="-stdlib=libc++" architecture=${ARCHITECTURE} target-os=iphone \
     address-model=${ADDRESS_MODEL} abi=${ABI} binary-format=mach-o \
     macosx-version=${BOOST_PLAT}-${SDK_VER} define=_LITTLE_ENDIAN link=static install
    doneSection
}

#===============================================================================

scrunchAllLibsTogetherInOneLib()
{
    OBJDIR=$BOOST_SOURCE_NAME/tmp/obj
    mkdir -p $OBJDIR

    for a in $ROOTDIR/lib/libboost_*.a ; do
        echo thining $a...
        lipo -info $a 
        FAT_FILE=$(lipo -info $a | grep "fat file")
        if [ "${FAT_FILE}" != "" ]
        then
            echo "fat file and lipo thin $ARCH $a"
            lipo -thin $ARCH $a -output $a
        fi
        echo Decomposing $a...
        (cd $OBJDIR; ${AR} -x $a );
    done;

    echo creating $ROOTDIR/lib/libboost.a
    (cd $OBJDIR; ${AR} crus $ROOTDIR/lib/libboost.a *.o; )
}

#===============================================================================
# Execution starts here
#===============================================================================

[ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

cleanEverythingReadyToStart
unpackBoost
#cd $BOOST_SOURCE_NAME
#inventMissingHeaders
bootstrapBoost
writeBjamUserConfig
buildBoostForiPhoneOS
scrunchAllLibsTogetherInOneLib

echo "Completed successfully"

