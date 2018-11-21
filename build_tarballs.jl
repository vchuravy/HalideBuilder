# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "HalideBuilder"
version = v"0.0.1"

# Collection of sources required to build HalideBuilder
sources = [
    "https://github.com/halide/Halide/archive/release_2018_02_15.tar.gz" =>
    "0c26375ad8016f0bf96d67b1283020900197329b6d73e5f9fa27c082a38a2742",
]

# Dependencies that must be installed before this package can be built
dependencies = [
    "https://github.com/staticfloat/LLVMBuilder/releases/download/v6.0.1-3%2Bnowasm/build_LLVM.v6.0.1.jl"
]

# setup script
script_setup = raw"""
cd $WORKSPACE/srcdir/Halide*
sed -i 's/LLVM_TOOLS_BINARY_DIR/LLVM_TOOLS_INSTALL_DIR/g' CMakeLists.txt
mkdir build
pushd build
cmake -GNinja -DLLVM_DIR=$prefix/lib/cmake/llvm -DWITH_TESTS=off -DWITH_TUTORIALS=off -DWITH_APPS=off \
      -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE=/opt/$target/$target.toolchain ..
mkdir -p $prefix/bin
export PATH=$prefix/bin:$PATH
"""

# build the native tools directly

script = script_setup * raw"""
ninja binary2cpp build_halide_h
mv bin/binary2cpp $prefix/bin/
mv bin/build_halide_h $prefix/bin/
"""

platforms = [
    Linux(:x86_64, :musl),
]

products(prefix) = [
    ExecutableProduct(prefix, "binary2cpp", :binary2cpp)
    ExecutableProduct(prefix, "build_halide_h", :build_halide_h)
    ExecutableProduct(prefix, "llvm-config", :llvm_config)
]

# Build the tarball, overriding ARGS so that the user doesn't shoot themselves in the foot,
# but only do this if we don't already have a native tarball available:
native_tarball = joinpath("products", "native.x86_64-linux-musl.tar.gz")
if !isfile(native_tarball)
    native_ARGS = ["x86_64-linux-musl"]
    if "--verbose" in ARGS
        push!(native_ARGS, "--verbose")
    end
    product_hashes = build_tarballs(native_ARGS, "native", version, sources, script, platforms, products, dependencies)

    # Extract path information to the built native tarball and its hash
    native_tarball, native_hash = product_hashes["x86_64-linux-musl"]
    native_tarball = joinpath("products", native_tarball)
else
    info("Using pre-built native tarball at $(native_tarball)")
    using SHA: sha256
    native_hash = open(native_tarball) do f
        bytes2hex(sha256(f))
    end
end

# Take that tarball, feed it into our next build as another "source".
push!(sources, native_tarball => native_hash)

# Bash recipe for building across all platforms
script = script_setup * raw"""
ninja
ninja install
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Linux(:x86_64, libc=:glibc)
]

# The products that we will ensure are always built
products(prefix) = [
    LibraryProduct(prefix, "libHalide", :halide)
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)
