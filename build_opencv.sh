#!/bin/bash

# build_opencv -*- shell-script -*-
#
# The MIT License (MIT)
#
# Copyright (c) 2017 Leonardo Lontra
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# builtin variables
RED='\033[0;31m'
BLUE='\033[1;36m'
NC='\033[0m'
OPENCV_VERSION="master"
OPENCV_SRC_FILENAME="opencv.zip"
OPENCV_CONTRIB_SRC_FILENAME="opencv-contrib.zip"

DIR="$(realpath $(dirname $0))"
source "${DIR}/deps.sh"

function log_failure_msg() {
    echo -ne "[${RED}error${NC}] $@\n"
}


function log_warn_msg() {
    echo -ne "[${RED}warn${NC}] $@\n"
}


function log_app_msg() {
    echo -ne "[${BLUE}info${NC}] $@\n"
}


function yesnoPrompt() {
    local response=""
    read -p "$1" -r response
    [[ $response =~ ^[Yy]$ ]] && return 0
    return 1
}


function makeBuildDirAndGo() {
    mkdir ${WORKDIR}/opencv-${OPENCV_VERSION}/build/ 2>/dev/null
    cd ${WORKDIR}/opencv-${OPENCV_VERSION}/build/
}


function dw_opencv() {
    [ -z "$OPENCV_VERSION" ] && {
        log_failure_msg "Variable OPENCV_VERSION is not set."
        return 1
    }

    mkdir -p $WORKDIR

    if [ -d ${WORKDIR}/opencv-${OPENCV_VERSION}/ ]; then
        log_app_msg "opencv exists."
        return 0
    fi

    [ -f "$OPENCV_SRC_FILENAME" ] && rm -f "$OPENCV_SRC_FILENAME"

    log_app_msg "Downloading opencv https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip..."
    wget --no-check-certificate -q -c https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip -O "$OPENCV_SRC_FILENAME" || return 1

    unzip -o $OPENCV_SRC_FILENAME -d "$WORKDIR" 1>/dev/null || {
        log_failure_msg "error on uncompress opencv src"
        return 1
    }

    return 0
}


function dw_opencv_contrib() {
    [ -z "$OPENCV_VERSION" ] && {
        log_failure_msg "Variable OPENCV_VERSION is not set."
        return 1
    }

    if [ -d ${WORKDIR}/opencv-${OPENCV_VERSION}/opencv_contrib ]; then
        log_app_msg "opencv-contrib exists."
        return 0
    fi

    [ -f "$OPENCV_CONTRIB_SRC_FILENAME" ] && rm -f "$OPENCV_CONTRIB_SRC_FILENAME"

    log_app_msg "Downloading opencv contrib https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip..."
    wget --no-check-certificate -q -c https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip -O "$OPENCV_CONTRIB_SRC_FILENAME" || return 1

    unzip -o "$OPENCV_CONTRIB_SRC_FILENAME" -d "${WORKDIR}/opencv-${OPENCV_VERSION}/" 1>/dev/null || {
        log_failure_msg "error on uncompress opencv contrib"
        exit 1
    }
    mv "${WORKDIR}/opencv-${OPENCV_VERSION}/opencv_contrib-${OPENCV_VERSION}/" "${WORKDIR}/opencv-${OPENCV_VERSION}/opencv_contrib"

    return 0
}


function dw_toolchain() {
    [ "$CROSS_COMPILER" != "yes" ] && return 0

    if [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/bin/" ]; then
        log_app_msg "toolchain exists."
        return 0
    fi

    log_app_msg "Downloading toolchain ${CROSSTOOL_URL}"

    mkdir -p ${WORKDIR}/toolchain/
    wget --no-check-certificate -q -c $CROSSTOOL_URL -O ${WORKDIR}/toolchain/toolchain.tar.xz || {
      log_failure_msg "error when download toolchain."
      return 1
    }

    tar xf ${WORKDIR}/toolchain/toolchain.tar.xz -C ${WORKDIR}/toolchain/ || {
      log_failure_msg "error when extract toolchain."
      return 1
    }

    rm -f ${WORKDIR}/toolchain/toolchain.tar.xz  &>/dev/null

    return 0
}


function cmakegen() {
    log_app_msg "execute cmake..."

    # clean build folder
    if [ -d ${WORKDIR}/opencv-${OPENCV_VERSION}/build/ ]; then
        log_warn_msg "Clean build files if you want compile for another target. Use $0 -c <configfile> --cleanup"
        sleep 1
    fi

    [ -d "${WORKDIR}/opencv-${OPENCV_VERSION}/opencv_contrib" ] && FLAGS+=" -D OPENCV_EXTRA_MODULES_PATH=../opencv_contrib/modules"

    local deps_path="${WORKDIR}/cross_deps/deps/${CROSSTOOL_ARCH}"
    local cv_compileOptions="${WORKDIR}/opencv-${OPENCV_VERSION}/cmake/OpenCVCompilerOptions.cmake"
    local toolchain_cmakefile="${WORKDIR}/opencv-${OPENCV_VERSION}/${CROSSTOOL_CMAKE_TOOLCHAIN_FILE}"

    # preserve modified files
    if [ -f "$toolchain_cmakefile" ]; then
        if [ ! -f "${toolchain_cmakefile}.orig" ]; then
            cp -a "$toolchain_cmakefile" "${toolchain_cmakefile}.orig"
        else
            cp -a "${toolchain_cmakefile}.orig" "${toolchain_cmakefile}"
        fi
    fi

    if [ -f "$cv_compileOptions" ]; then
        if [ ! -f "${cv_compileOptions}.orig" ]; then
            cp -a "$cv_compileOptions" "${cv_compileOptions}.orig"
        else
            cp -a "${cv_compileOptions}.orig" "${cv_compileOptions}"
        fi
    fi

    if [ "$CROSS_COMPILER" == "yes" ] && [ ! -d "${deps_path}" ]; then
        log_warn_msg "Cross-compiler without local dependencies. "
        sleep 1
    fi

    # fix missing headers of blas/lapack inn crosscompilation mode
    if [ "$CROSS_COMPILER" == "yes" ] && [ ! -f  "${deps_path}"/usr/include/cblas.h ]; then
        echo "$FLAGS" | grep "WITH_LAPACK=ON" 1>/dev/null && {
            local blas_lapack_dir="$(dirname $(find "${deps_path}" -iwholename '*include*/*blas*' | grep -v 'Eigen' | tail -n1))"
            cp -a "${blas_lapack_dir}"/cblas-atlas.h "${deps_path}"/usr/include/cblas.h &>/dev/null
            cp -a "${blas_lapack_dir}"/cblas* "${deps_path}"/usr/include/ &>/dev/null
            cp -a "${blas_lapack_dir}"/clapack.h "${deps_path}"/usr/include/ &>/dev/null
            log_warn_msg "install liblapacke-dev${CROSSTOOL_ARCH} again"
            sleep 10
        }
    fi

    if [ "$CROSS_COMPILER" == "yes" ]; then
        # finds the include folder of cross-compiler toolchain
        local gcc_version=$(${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-gcc -dumpversion)
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/include/c++/${gcc_version}" ] && EXTRA_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/include/c++/${gcc_version}"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/include" ] && EXTRA_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/$CROSSTOOL_NAME/sysroot/usr/include"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/include" ] && EXTRA_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/$CROSSTOOL_NAME/libc/usr/include"
        [ -d "${CROSSTOOL_DIR}/lib/gcc/${CROSSTOOL_NAME}/${gcc_version}/include" ] && EXTRA_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/lib/gcc/$CROSSTOOL_NAME/${gcc_version}/include"
        [ -d "${CROSSTOOL_DIR}/lib/gcc/${CROSSTOOL_NAME}/${gcc_version}/include-fixed" ] && EXTRA_CXX_FLAGS+=" -isystem ${CROSSTOOL_DIR}/lib/gcc/$CROSSTOOL_NAME/${gcc_version}/include-fixed"

        # finds the libraries folder of cross-compiler toolchain
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib" ] && EXTRA_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib" ] && EXTRA_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot/usr/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib" ] && EXTRA_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/lib"
        [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib" ] && EXTRA_CXX_FLAGS+=" -L${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib -Wl,-rpath-link,${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc/usr/lib"

        # fixes some undefined symbol issues
        EXTRA_CXX_FLAGS+=" -Wl,--unresolved-symbols=ignore-all"

        # needs for linking opencv libraries in tbb.so
        EXTRA_CXX_FLAGS+=" -Wl,-rpath-link,${WORKDIR}/opencv-${OPENCV_VERSION}/build/lib"

        if [ -d "${deps_path}" ]; then
            [ -f "${deps_path}/.sysinclude" ] && EXTRA_CXX_FLAGS+=" $(cat "${deps_path}/.sysinclude")"
            [ -f "${deps_path}/.syslib" ] && EXTRA_CXX_FLAGS+=" $(cat "${deps_path}/.syslib")"
            [ -f "${deps_path}/.rpath_link" ] && EXTRA_CXX_FLAGS+=" $(cat "${deps_path}/.rpath_link")"
        fi

        if [ -f "$toolchain_cmakefile" ]; then

            local toolchain_sysroot=""
            [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot" ] && toolchain_sysroot+="\"${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/sysroot\""
            [ -d "${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc" ] && toolchain_sysroot+="\"${CROSSTOOL_DIR}/${CROSSTOOL_NAME}/libc\""

            # finds library outside cross_deps folder, if exists ld.so.conf.d
            local pre_root_path=""
            [ -f /etc/ld.so.conf.d/${CROSSTOOL_NAME}.conf ] && pre_root_path+="$(cat /etc/ld.so.conf.d/${CROSSTOOL_NAME}.conf | grep -v '^#' | tr '\n' ' ')"

            # configure cmake of crosscompile
            local pattern="/include(/i"
            pattern+="\set (CMAKE_FIND_ROOT_PATH ${toolchain_sysroot} \"${pre_root_path}\" \"${deps_path}\")\n"
            pattern+="set (CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)\n"
            pattern+="set (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)\n"
            pattern+="set (CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)\n"
            pattern+="set (OPENCV_EXTRA_C_FLAGS "\"${EXTRA_CXX_FLAGS}\"")\n"
            pattern+="set (OPENCV_EXTRA_CXX_FLAGS "\"${EXTRA_CXX_FLAGS}\"")\n"
            sed -i "$pattern" ${toolchain_cmakefile}
        fi

    fi

    # necessary for build opencv <= 3.4.0
    if [ ! -z "$EXTRA_CXX_FLAGS" ]; then
        log_app_msg "exporting cflags..."
        sed -i "/set(OPENCV_EXTRA_C_FLAGS \"\")/c\set(OPENCV_EXTRA_C_FLAGS \"${EXTRA_CXX_FLAGS}\")" ${cv_compileOptions}
        sed -i "/set(OPENCV_EXTRA_CXX_FLAGS \"\")/c\set(OPENCV_EXTRA_CXX_FLAGS \"${EXTRA_CXX_FLAGS}\")" ${cv_compileOptions}
        export CFLAGS="$EXTRA_CXX_FLAGS"
        export CXXFLAGS="$EXTRA_CXX_FLAGS"
        FLAGS+=" -DEXTRA_C_FLAGS=$EXTRA_CXX_FLAGS -DEXTRA_CXX_FLAGS=$EXTRA_CXX_FLAGS"
    fi

    makeBuildDirAndGo

    [ "$CROSS_COMPILER" == "yes" ] && {

        echo "$FLAGS" | grep "BUILD_opencv_python2=ON" 1>/dev/null && {

            if [ ! -d "${deps_path}" ]; then
              log_warn_msg "not found cross libraries path."
              echo "Please runs this command: $0 -c <configfile> --check-deps"
              return 1
            fi

            # finds python2 libraries
            if [ "$PYTHON_VENV" == "ON" ]; then
                local py2_np_inc="$(python -c 'import numpy as np;print(np.get_include())')"
                local py2_executable="$(command -v python)"
                local py2_numpy_version="$(python -c 'import numpy as np;print(np.__version__)')"
            else
                local py2_np_inc="$(find ${deps_path}/ -wholename '*python2*numpy*core*include' | head -n1)"
                local py2_executable=$(find ${deps_path}/ -type f -wholename '*bin/python2*' | sort | head -n1)
                local py2_numpy_version="$(cat $(find ${deps_path}/ -wholename '*python2*numpy-*.egg*' | grep -i 'PKG-INFO') | grep -i "version" | tail -n1 | awk '{ print $2 }')"
            fi
            local py2_inc="$(find ${deps_path}/ -type d -wholename '*include/python2*')"
            local py2_lib="$(find ${deps_path}/ -iname '*libpython2*.so' | head -n1)"

            if [ -z "$py2_executable" ]; then
              log_failure_msg "not found python${py2_version} executable."
              exit 1
            fi

            if [ -z "$py2_inc" ]; then
              log_failure_msg "not found python2 include path."
              exit 1
            fi

            if [ -z "$py2_lib" ]; then
              log_failure_msg "not found python2 libraries path."
              exit 1
            fi

            if [ -z "$py2_np_inc" ]; then
              log_failure_msg "not found numpy for python2 include path."
              exit 1
            fi

            # uses same python executable in crosscompiler
            FLAGS+=" -DPYTHON2_EXECUTABLE=${py2_executable}"
            FLAGS+=" -DPYTHON2_INCLUDE_PATH=${py2_inc}"
            FLAGS+=" -DPYTHON2_LIBRARIES=${py2_lib}"
            FLAGS+=" -DPYTHON2_NUMPY_INCLUDE_DIRS=${py2_np_inc}"
            FLAGS+=" -DPYTHON2_NUMPY_VERSION=${py2_numpy_version}"
        }

        echo "$FLAGS" | grep "BUILD_opencv_python3=ON" 1>/dev/null && {

            if [ ! -d "${deps_path}" ]; then
              log_warn_msg "not found cross libraries path."
              echo "Please runs this command: $0 -c <configfile> --check-deps"
              return 1
            fi

            # finds python3 libraries
            if [ "$PYTHON_VENV" == "ON" ]; then
                local py3_np_inc="$(python -c 'import numpy as np;print(np.get_include())')"
                local py3_executable="$(command -v python)"
                local py3_numpy_version="$(python -c 'import numpy as np;print(np.__version__)')"
            else 
                local py3_np_inc="$(find ${deps_path}/ -wholename '*python3*numpy*core*include' | head -n1)"
                local py3_executable=$(find ${deps_path}/ -type f -wholename '*bin/python3*' | sort | head -n1)
                local py3_numpy_version="$(cat $(find ${deps_path}/ -wholename '*python3*numpy-*.egg*' | grep -i 'PKG-INFO') | grep -i "version" | tail -n1 | awk '{ print $2 }')"
            fi
            local py3_inc="$(find ${deps_path}/ -type d -wholename '*include/python3*')"
            local py3_lib="$(find ${deps_path}/ -iname '*libpython3*.so' | head -n1)"

            if [ -z "$py3_executable" ]; then
              log_failure_msg "not found python${py3_version} executable."
              exit 1
            fi

            if [ -z "$py3_inc" ]; then
              log_failure_msg "not found python3 include path."
              exit 1
            fi

            if [ -z "$py3_lib" ]; then
              log_failure_msg "not found python3 libraries path."
              exit 1
            fi

            if [ -z "$py3_np_inc" ]; then
              log_failure_msg "not found numpy for python3 include path."
              exit 1
            fi

            # uses same python executable in crosscompiler
            FLAGS+=" -DPYTHON3_EXECUTABLE=${py3_executable}"
            FLAGS+=" -DPYTHON3_INCLUDE_PATH=${py3_inc}"
            FLAGS+=" -DPYTHON3_LIBRARIES=${py3_lib}"
            FLAGS+=" -DPYTHON3_NUMPY_INCLUDE_DIRS=${py3_np_inc}"
            FLAGS+=" -DPYTHON3_NUMPY_VERSION=${py3_numpy_version}"
        }

        FLAGS+=" -DGCC_COMPILER_VERSION=${gcc_version}"
        FLAGS+=" -DCMAKE_LINKER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ld"
        FLAGS+=" -DCMAKE_AR=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ar"
        FLAGS+=" -DCMAKE_NM=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-nm"
        FLAGS+=" -DCMAKE_OBJCOPY=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-objcopy"
        FLAGS+=" -DCMAKE_OBJDUMP=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-objdump"
        FLAGS+=" -DCMAKE_RANLIB=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-ranlib"
        FLAGS+=" -DCMAKE_STRIP=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-strip"
        FLAGS+=" -DCMAKE_C_COMPILER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-gcc"
        FLAGS+=" -DCMAKE_CXX_COMPILER=${CROSSTOOL_DIR}/bin/${CROSSTOOL_NAME}-g++"
        # fix some toolchains that do not support -mthumb
        if [ ! -z "${CROSSTOOL_C_CXX_FLAGS}" ]; then
            FLAGS+=" -DCMAKE_C_FLAGS=${CROSSTOOL_C_CXX_FLAGS}"
            FLAGS+=" -DCMAKE_CXX_FLAGS=${CROSSTOOL_C_CXX_FLAGS}"
        fi
        FLAGS+=" -DCMAKE_TOOLCHAIN_FILE=${toolchain_cmakefile}"

        # enable pkg-config if variable exists
        [ "$CROSS_COMPILER" == "yes" ] && [ -d "${deps_path}" ] && [ -f "${deps_path}/.pkgconfig" ] && {
            source "${deps_path}/.pkgconfig"
            export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
            export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
            FLAGS+=" -DPKG_CONFIG_EXECUTABLE=$(command -v pkg-config)"
        }
    }

    FLAGS+=" .."
    cmake $FLAGS || return 1
}


function checkinstallgen() {
    makeBuildDirAndGo

    # prepare postinstall
    echo -ne '#!/bin/bash\n\n' > postinstall-pak
    echo "echo \"${CMAKE_INSTALL_PREFIX}/lib\" > /etc/ld.so.conf.d/opencv.conf" >> postinstall-pak
    echo "ldconfig" >> postinstall-pak
    chmod +x postinstall-pak

    local opencv_version="$(cat ${WORKDIR}/opencv-${OPENCV_VERSION}/modules/core/include/opencv*/core/version.hpp)"
    local opencv_version_major=$(echo "$opencv_version" | grep -i '#define CV_VERSION_MAJOR' | awk '{ print $3 }')
    local opencv_version_minor=$(echo "$opencv_version" | grep -i '#define CV_VERSION_MINOR' | awk '{ print $3 }')
    local opencv_version_revision=$(echo "$opencv_version" | grep -i '#define CV_VERSION_REVISION' | awk '{ print $3 }')

    CHECKINSTALL_FLAGS="-y --backup=no --install=no -D"
    [ "$CHECKINSTALL_INCLUDE_DOC" == "no" ] && CHECKINSTALL_FLAGS+=" --nodoc"
    CHECKINSTALL_FLAGS+=" --pkgname=$CHECKINSTALL_PKGNAME"
    CHECKINSTALL_FLAGS+=" --pkgversion=${opencv_version_major}.${opencv_version_minor}.${opencv_version_revision}"
    CHECKINSTALL_FLAGS+=" --pkgsource=$CHECKINSTALL_PKGSRC"
    CHECKINSTALL_FLAGS+=" --pkggroup=$CHECKINSTALL_PKGGROUP"
    CHECKINSTALL_FLAGS+=" --pkgaltsource=$CHECKINSTALL_PKGALTSRC"
    CHECKINSTALL_FLAGS+=" --maintainer=$CHECKINSTALL_MANTAINER"
    [ "$CROSS_COMPILER" == "yes" ] && CHECKINSTALL_FLAGS+=" --pkgarch=$CROSSTOOL_ARCH --strip=no --stripso=no"

    echo -ne "$CHECKINSTALL_SUMMARY\n" > description-pak

    checkinstall $CHECKINSTALL_FLAGS make install || return 1
}


function makecv() {
    [ "$USE_CORES" == "all" ] && USE_CORES=$(nproc)
    make -j $USE_CORES || {
        log_failure_msg "ERROR: failed make"
        return 1
    }
    return 0
}


function check_loadedConfig() {
    if [ -z "$WORKDIR" ]; then
        log_failure_msg "ERROR: config not found"
        exit 1
    fi

    WORKDIR=$(realpath "$WORKDIR")
    OPENCV_SRC_FILENAME="${WORKDIR}/${OPENCV_SRC_FILENAME}"
    OPENCV_CONTRIB_SRC_FILENAME="${WORKDIR}/${OPENCV_CONTRIB_SRC_FILENAME}"
    CROSSTOOL_DIR="${WORKDIR}/toolchain/${CROSSTOOL_DIR}/"

    if [ "$CROSS_COMPILER" == "yes" ]; then
        for var in {CROSSTOOL_URL,CROSSTOOL_DIR,CROSSTOOL_NAME,CROSSTOOL_ARCH}; do
            eval "[ -z \"$"$var"\" ] && { echo log_failure_msg \"Variable $var is not set.\" ; exit 1; }"
        done
    fi

    for var in {CHECKINSTALL_INCLUDE_DOC,CHECKINSTALL_PKGNAME,CHECKINSTALL_PKGSRC,CHECKINSTALL_PKGGROUP,CHECKINSTALL_PKGALTSRC,CHECKINSTALL_MANTAINER,CHECKINSTALL_SUMMARY}; do
        eval "[ -z \"$"$var"\" ] && { echo log_failure_msg \"Variable $var is not set.\" ; exit 1; }"
    done
}


function usage() {
    echo -ne "Usage: $0 [-c|--source] [-b|--build] [-d|--check-deps] [-dw|--dw-cross-deps] [--clean] [--clean-cross-deps] [--clean-cv-sources ]\nOptions:\t
    -c, --config                                                                 load config.
    -b. --build                                                                  do all steps, checks dependencies, download sources & toolchain (if enabled) and build debian package.
    -d, --check-deps                                                             check opencv dependencies.
    -dw,--dw-cross-deps                                                          download custom packages list for selected archtecture (cross-compilation enabled only).
                                                                                 pkg-config, includes and libraries is configured for search in cross-compilation folder, for dependencies search automatically.
                                                                                 example:
                                                                                   $0 -c <configfile> --dw-cross-deps \"libavformat-dev:armhf libavcodec-dev:armhf\"
    --clean                                                                      clean build folder.
    --clean-cross-deps                                                           clean cross-compilation dependencies folder.
    --clean-cv-sources                                                           clean opencv folders.
    \n"
    exit 1
}

while [ "$1" != "" ]; do
    case $1 in
        -c|--config)
            source $2 2>/dev/null || {
                log_failure_msg "couldn't load config $2"
                exit 1
            }
            shift
        ;;
        -b|--build)
            check_loadedConfig
            install_deps || exit 1
            dw_opencv || exit 1
            dw_opencv_contrib || exit 1
            dw_toolchain || exit 1
            cmakegen || exit 1
            yesnoPrompt "Do you want continue? (next steps is execute make and generates debian package) [Y/n] " || exit 0
            makecv || exit 1
            checkinstallgen || exit 1
            exit 0
        ;;
        -d|--check-deps)
            check_loadedConfig
            install_deps || {
                log_failure_msg "failed when install dependencies"
                exit 1
            }
            exit 0
        ;;
        -dw|--dw-cross-deps)
            check_loadedConfig
            [ "$CROSS_COMPILER" != "yes" ] && {
                log_failure_msg "cross compiler is disabled."
                exit 1
            }
            fetch_cross_local_deps "$2"
            exit 0
        ;;
        --clean)
            check_loadedConfig
            rm -rf ${WORKDIR}/opencv-${OPENCV_VERSION}/build/
            log_app_msg "build folder was removed."
            exit 0
        ;;
        --clean-cross-deps)
            check_loadedConfig
            [ -z "$CROSSTOOL_ARCH" ] && {
                log_failure_msg "cross compiler is disabled."
                exit 1
            }
            rm -rf ${WORKDIR}/cross_deps/deps/${CROSSTOOL_ARCH}/
            rm -rf ${WORKDIR}/cross_deps/debs/${CROSSTOOL_ARCH}/
            log_app_msg "dependencies folder was removed."
            exit 0
        ;;
        --clean-cv-sources)
            check_loadedConfig
            rm -rf ${WORKDIR}/opencv-${OPENCV_VERSION}/
            log_app_msg "opencv folder was removed."
            exit 0
        ;;
        *)
            usage
        ;;
    esac
    shift
done
