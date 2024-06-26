#!/bin/bash

function fetch_cross_local_deps() {
    local packages="$1"
    [ -z "$packages" ] && {
        log_warn_msg "not found $packages"
        return 1
    }

    local deb_path="${WORKDIR}/cross_deps/debs/${CROSSTOOL_ARCH}"
    local deps_path="${WORKDIR}/cross_deps/deps/${CROSSTOOL_ARCH}"

    mkdir -p $deb_path
    mkdir -p $deps_path

    # creates a temporary dpkg status
    local temp_dpkg_status="${deb_path}/.status"
    > $temp_dpkg_status

    local pkg_list=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends -o Dir::State::status=${temp_dpkg_status} $packages)
    local urls=$(apt-get download --print-uris --allow-unauthenticated -o Dir::State::status=${temp_dpkg_status} $pkg_list 2>&1 | grep "http" |  awk '{ print $1 }' | tr -d "'")

    for url in $urls; do
        log_app_msg "Downloading: $url"
        wget -q -c $url -P ${deb_path}/
        log_app_msg "extracting package $(basename $url)"
        dpkg -x ${deb_path}/$(basename $url) ${deps_path}/
    done

    local new_loc=$(echo "$deps_path/usr" | sed 's./.\\/.g')
    local export_pkgconfig_path=""

    for d in $(find ${deps_path}/ -type d -iname '*pkgconfig*'); do
        export_pkgconfig_path+="${d}:"

        for f in $(find $d -type f); do
            cat $f | grep -iq "${deps_path}" || sed -i "s/\/usr/${new_loc}/g" $f 2>/dev/null
        done

    done

    [ ! -z "$export_pkgconfig_path" ] && export_pkgconfig_path="PKG_CONFIG_LIBDIR=\"${export_pkgconfig_path:0:-1}\""

    echo "${export_pkgconfig_path}" > ${deps_path}/.pkgconfig

    # finds includes dir
    local sys_include=""
    for inc_dir in {/usr/include,/usr/local/include}; do
        [ -d ${deps_path}/${inc_dir} ] && sys_include+=" -isystem ${deps_path}/${inc_dir}"
        [ -d ${deps_path}/${inc_dir}/${CROSSTOOL_NAME} ] && sys_include+=" -isystem ${deps_path}/${inc_dir}/${CROSSTOOL_NAME}"
    done
    echo "$sys_include" > ${deps_path}/.sysinclude

    local sys_lib=""
    local rpathlink=""
    for inc_lib in {/usr/lib,/lib}; do
        [ -d ${deps_path}/${inc_lib} ] && {
            sys_lib+=" -L${deps_path}/${inc_lib}"
            rpathlink+=" -Wl,-rpath-link,${deps_path}/${inc_lib}"
        }
        [ -d ${deps_path}/${inc_lib}/${CROSSTOOL_NAME} ] && {
            sys_lib+=" -L${deps_path}/${inc_lib}/${CROSSTOOL_NAME}"
            rpathlink+=" -Wl,-rpath-link,${deps_path}/${inc_lib}/${CROSSTOOL_NAME}"
        }
    done
    echo "${rpathlink}" > ${deps_path}/.rpath_link
    echo "$sys_lib" > ${deps_path}/.syslib

    cd ${WORKDIR}

}

function install_deps() {

    yesnoPrompt "Do you want install/check dependencies? [Y/n] " || return 0

    log_app_msg "Checking dependencies..."

    local arch=""
    local make_local_deps="no"
    local fetch_packages=""
    local package_file=""

    # install deps for selected arch
    [ "$CROSS_COMPILER" == "yes" ] && {
        arch=":${CROSSTOOL_ARCH}"
        log_warn_msg "NOTE: make sure you have added the architecture ${CROSSTOOL_ARCH} before execute this command. (dpkg --add-architecture ${CROSSTOOL_ARCH}).
                      Some packages can broken during installation in debian multiarch.
                      We have a utility that downloads recursive dependencies and adjusts its paths."

        yesnoPrompt "Do you want to automatically download these dependencies locally? [Y/n] " && make_local_deps="yes"
    }

    package_file="wget unzip checkinstall build-essential cmake yasm pkg-config"
    for p in $package_file; do
        yesnoPrompt "install package: $p [Y/n] " && apt-get --allow-unauthenticated install $p || {
                    log_warn_msg "couldn't install $p"
        }
    done

    echo "$FLAGS" | grep "V4L=ON" 1>/dev/null && {
        apt-get --allow-unauthenticated install libv4l-dev || {
            log_warn_msg "couldn't install libv4l-dev"
        }
    }

    echo "$FLAGS" | grep "WITH_EIGEN=ON" 1>/dev/null && {
        package_file="libeigen3-dev"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $package_file || {
                log_warn_msg "couldn't install $package_file"
            }
        else
            yesnoPrompt "Download local packages: $package_file [Y/n] " && fetch_cross_local_deps "$package_file"
        fi
    }

    echo "$FLAGS" | grep "WITH_OPENCL=ON" 1>/dev/null && {
        apt-get --allow-unauthenticated install opencl-headers || {
            log_warn_msg "couldn't install opencl-headers"
        }
    }

    echo "$FLAGS" | grep "WITH_GSTREAMER=ON" 1>/dev/null && {
        package_file="libgstreamer1.0-dev${arch} libgstreamer-plugins-base1.0-dev${arch}"
        for p in $package_file; do
            if [ "$make_local_deps" == "no" ]; then
                apt-get --allow-unauthenticated install $p || {
                    log_warn_msg "couldn't install $p"
                }
            else
                yesnoPrompt "Download local packages: $p [Y/n] " && fetch_cross_local_deps "$p"
            fi
        done
    }

    echo "$FLAGS" | grep "WITH_OPENCLAMDBLAS=ON" 1>/dev/null && {
        package_file="libclblas-dev${arch}"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $package_file || {
                log_warn_msg "couldn't install $package_file"
            }
        else
            yesnoPrompt "Download local packages: $package_file [Y/n] " && fetch_cross_local_deps "$package_file"
        fi
    }

    package_file="libatlas-dev${arch} libopenblas-dev${arch} libatlas-base-dev${arch} liblapacke-dev${arch}"
    for p in $package_file; do
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $p || {
                log_warn_msg "couldn't install $p"
            }
        else
            yesnoPrompt "Download local packages: $p [Y/n] " && fetch_cross_local_deps "$p"
        fi
    done

    echo "$FLAGS" | grep "WITH_GTK=ON" 1>/dev/null && {
        yesnoPrompt "Gtk gui was selected, whats version [2/3] " && package_file="libgtk2.0-dev${arch}" || package_file="libgtk-3-dev${arch}"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $package_file || {
                log_warn_msg "couldn't install $package_file"
            }
        else
            yesnoPrompt "Download local packages: $package_file [Y/n] " && fetch_cross_local_deps "$package_file"
        fi
    }

    echo "$FLAGS" | grep "WITH_QT=ON" 1>/dev/null && {
        package_file="qt5-default${arch} qtbase5-dev${arch}"
        for p in $package_file; do
            if [ "$make_local_deps" == "no" ]; then
                apt-get --allow-unauthenticated install $p || {
                    log_warn_msg "couldn't install $p"
                }
            else
                yesnoPrompt "Download local packages: $p [Y/n] " && fetch_cross_local_deps "$p"
            fi
        done
    }

    echo "$FLAGS" | grep "WITH_FFMPEG=ON" 1>/dev/null && {
        package_file="libavcodec-dev${arch} libavformat-dev${arch} libswscale-dev${arch} libavresample-dev${arch} libx264-dev${arch} libavutil-dev${arch}"
        for p in $package_file; do
            if [ "$make_local_deps" == "no" ]; then
                apt-get --allow-unauthenticated install $p || {
                    log_warn_msg "couldn't install $p"
                }
            else
                yesnoPrompt "Download local packages: $p [Y/n] " && fetch_cross_local_deps "$p"
            fi
        done
    }

    echo "$FLAGS" | grep "WITH_1394=ON" 1>/dev/null && {
        package_file="libdc1394-22-dev${arch}"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install ${package_file} || {
                log_warn_msg "couldn't install ${package_file}"
            }
        else
            yesnoPrompt "Download local packages: $package_file [Y/n] " && fetch_cross_local_deps "$package_file"
        fi
    }

    echo "$FLAGS" | grep "BUILD_opencv_python2=ON" 1>/dev/null && {
        package_file="libpython-all-dev${arch} libpython-dev${arch} python-dev${arch} python-numpy"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $package_file || {
                log_warn_msg "couldn't install $package_file"
            }
        else
            yesnoPrompt "Download local packages: ${package_file}${arch} [Y/n] " && fetch_cross_local_deps "${package_file}${arch}"
        fi
    }

    echo "$FLAGS" | grep "BUILD_opencv_python3=ON" 1>/dev/null && {
        package_file="libpython3-all-dev${arch} libpython3-dev${arch} python3-dev${arch} python3-numpy"
        if [ "$make_local_deps" == "no" ]; then
            apt-get --allow-unauthenticated install $package_file || {
                log_warn_msg "couldn't install $package_file"
            }
        else
            yesnoPrompt "Download local packages: ${package_file}${arch} [Y/n] " && fetch_cross_local_deps "${package_file}${arch}"
        fi
    }

    return 0
}
