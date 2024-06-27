# build_opencv

Multiarch cross compiling environment for opencv

## Edit tweaks like flags to enable or disable features, toolchain url, and others
see configuration file examples in: configs/

## Cross-compilation
For example, let's demonstrates how to cross-compile to raspberry pi using gcc linaro.
Make you sure added arm architecture, see how to adds in debian flavors:
```shell
dpkg --add-architecture armhf
apt-get update
```
```shell
./build_opencv.sh -c configs/rpi_linaro.conf --build
# will be asked to download the dependencies, we recommended dependencies downloads locally. The script will configure pkg-config so that opencv's cmake will detect selected libraries in config.
# If you selected, for example, backend gstreamer, the script no ask if you wants download dependencies, use:
./build_opencv.sh -c configs/rpi_linaro.conf --dw-cross-deps "libgstreamer1.0-dev=armhf libgstreamer-plugins-base1.0-dev=armhf"

# For next build
./build_opencv.sh -c configs/rpi_linaro.conf --clean # copy debian package before execute this command.
./build_opencv.sh -c configs/odroidc2.conf --build
```

## issues
opencv 4.10.0 fails when build with tbb.
for  fix issue, replace `3rdparty/tbb/CMakeLists.txt` for https://github.com/opencv/opencv/blob/4.9.0/3rdparty/tbb/CMakeLists.txt 

## License
The file LICENSE applies to other files in this repository. I want to stress that a majority of the lines of code found in the guide of this repository was created by others. If any of those original authors want more prominent attribution, please contact me and we can figure out how to make it acceptable.
