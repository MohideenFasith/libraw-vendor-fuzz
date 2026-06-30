#!/bin/bash -eu
#
# ClusterFuzzLite build script for LibRaw.
#
# Builds the LibRaw static library (autotools) and links it with the
# vendor-format fuzz harness. Uses the CC / CXX / CFLAGS / CXXFLAGS /
# LIB_FUZZING_ENGINE environment variables provided by the build
# infrastructure rather than hardcoding our own compiler or sanitizer
# flags, so this works unmodified under whatever sanitizer configuration
# is in use.
#
# This harness focuses on vendor RAW formats that LibRaw's own upstream
# OSS-Fuzz integration does not seed (its three named fuzz targets are
# all the same generic harness, differentiated only by which of three
# seed corpora -- CR2, NEF, RAF -- gets paired with the binary). Sony,
# Olympus, Panasonic, Pentax, Samsung, Minolta, Leica, Hasselblad, Phase
# One, Mamiya, Sinar, Leaf, Imacon, SMaL, Rollei, and Sigma have no
# dedicated seeding upstream, so fuzz/corpus/ ships hand-built minimal
# TIFF structures (validated to correctly route through identify() and
# unpack() for each vendor) covering exactly that gap.
#
# No network access is used at any point in this script -- LibRaw's own
# source is vendored directly in this repository (RawSpeed/RawSpeed3,
# which are optional alternate decoder backends not used by this build
# path, were removed to keep the repository lean).

cd "$SRC"

# configure (and its supporting libtool/ltmain.sh/install-sh/aclocal.m4/
# Makefile.in/etc. files) are pre-generated and committed directly in
# this repository, since the oss-fuzz-base/base-builder image does not
# ship autoconf/automake/libtool, and the build runs with networking
# disabled so they can't be apt-installed at build time either.
#
# A plain checkout doesn't preserve the relative mtimes these files need
# (configure must be newer than configure.ac, Makefile.in newer than
# Makefile.am, etc.), so Automake's generated Makefile rules would
# otherwise try to regenerate them via the very tools we don't have.
# Touch the generated artifacts forward to keep those rules from
# triggering at all.
touch aclocal.m4 configure Makefile.in libraw.pc.in libraw_r.pc.in \
      libtool ltmain.sh install-sh missing compile depcomp \
      config.guess config.sub

# Re-assert executable bits and invoke configure via an explicit shell
# rather than direct execution (`./configure`). Git records these as
# mode 100755 in the repository, but whatever packages/extracts this
# submission for the build (the submission page referred to it as a
# .zip) may not preserve Unix permissions through that step, so don't
# depend on them surviving.
chmod +x configure libtool ltmain.sh install-sh missing compile depcomp \
         config.guess config.sub version.sh 2>/dev/null || true

sh ./configure --disable-examples --disable-jpeg --disable-zlib --disable-lcms

export CFLAGS="${CFLAGS:-} -DUSE_X3FTOOLS"
export CXXFLAGS="${CXXFLAGS:-} -DUSE_X3FTOOLS -std=c++17"

make -j"$(nproc)" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS"

$CXX $CXXFLAGS -Ilibraw \
  fuzz/libraw_vendor_fuzzer.cc \
  lib/.libs/libraw_r.a \
  $LIB_FUZZING_ENGINE \
  -o "$OUT/libraw_vendor_fuzzer"
