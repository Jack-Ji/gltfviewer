#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Need commit hash"
    exit 1
fi

rm -f $1.tar.gz
wget https://github.com/jack-ji/jok/archive/$1.tar.gz
zig fetch --save $1.tar.gz
sed -i "s/$1\.tar\.gz/git+https:\/\/github.com\/jack-ji\/jok.git#$1/" build.zig.zon
rm -f $1.tar.gz
