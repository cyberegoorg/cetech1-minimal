#!/bin/bash

set -x
set -e

git -C externals/cetech1/ submodule update --init

zig build init
zig build -Dexternals_optimize=Debug -Dwith_shaderc=false

ls -Rhan zig-out/
