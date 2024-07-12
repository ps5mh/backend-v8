#!/bin/bash

VERSION=$1
[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

if [ "$VERSION" == "10.6.194" -o "$VERSION" == "11.8.172" ]; then 
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python3 \
        ninja-build \
        xz-utils \
        zip
        
    pip install virtualenv
else
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python \
        xz-utils \
        zip
fi

sudo apt-get update
sudo apt-get install -y libatomic1-i386-cross
sudo rm -rf /var/lib/apt/lists/*
#export LD_LIBRARY_PATH=”LD_LIBRARY_PATH:/usr/i686-linux-gnu/lib/”
echo "/usr/i686-linux-gnu/lib" > i686.conf
sudo mv i686.conf /etc/ld.so.conf.d/
sudo ldconfig

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
cd depot_tools
git reset --hard 8d16d4a
cd ..
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$PATH
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['android']" >> .gclient
cd ~/v8/v8
./build/install-build-deps-android.sh
git checkout refs/tags/$VERSION

echo "=====[ fix DEPS ]===="
node -e "const fs = require('fs'); fs.writeFileSync('./DEPS', fs.readFileSync('./DEPS', 'utf-8').replace(\"Var('chromium_url') + '/external/github.com/kennethreitz/requests.git'\", \"'https://github.com/kennethreitz/requests'\"));"

echo "=====[ Patching V8 ]====="
git apply --cached $GITHUB_WORKSPACE/patches/v8_monolithic_no_dyn_symbol.patch
git checkout -- .

gclient sync


# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.8.172" ]; then 
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/remove_uchar_include_v11.8.172.patch
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION

echo "=====[ Building V8 ]====="
if [ "$VERSION" == "10.6.194" -o "$VERSION" == "11.8.172"  ]; then 
    gn gen out.gn/arm.release --args="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_absolute_paths_from_debug_symbols=false strip_debug_info=false symbol_level=1 use_custom_libcxx=false use_custom_libcxx_for_host=true v8_enable_sandbox=false"
else
    gn gen out.gn/arm.release --args="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_absolute_paths_from_debug_symbols=false strip_debug_info=false symbol_level=1 use_custom_libcxx=false use_custom_libcxx_for_host=true v8_expose_symbols=false v8_enable_webassembly=false v8_enable_lite_mode=true v8_monolithic_no_dyn_symbol=true"
fi
ninja -C out.gn/arm.release -t clean
ninja -v -C out.gn/arm.release v8_monolith

if [ "$VERSION" == "9.4.146.24" ]; then 
  third_party/android_ndk/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/arm-linux-androideabi/bin/strip -g -S -d --strip-debug --verbose out.gn/arm.release/obj/libv8_monolith.a
fi

mkdir -p output/v8/Lib/Android/armeabi-v7a
cp out.gn/arm.release/obj/libv8_monolith.a output/v8/Lib/Android/armeabi-v7a/
mkdir -p output/v8/Inc/Blob/Android/armv7a
