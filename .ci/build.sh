#!/bin/bash

set -x
set -e

zig build init
zig build -Dexternals_optimize=Debug -Dwith_shaderc=false

ls -Rhan zig-out/
