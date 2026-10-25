{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  git,
  python3,
  rocmPackages,
}:

# Strata 0.2 ソースコードビルド用 Derivation (AMD ROCm / gfx1102 ターゲット)
# コンパイルターゲットとして gfx1102 (Navi 33) を指定し、hipblas および hipblaslt をリンクしてビルドする。
stdenv.mkDerivation rec {
  pname = "strata-source";
  version = "0.2.6";

  src = fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "v${version}";
    hash = "sha256-HLlmKl+RDIP84KdifVUzduQ+ZN+51DbGaw9t+ITJkm8=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    git
    python3
    rocmPackages.clr
  ];

  buildInputs = [
    rocmPackages.clr
    rocmPackages.hipblas
    rocmPackages.hipblaslt
    rocmPackages.rocblas
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DSTRATA_ENABLE_HIP=ON"
    "-DSTRATA_ENABLE_CUDA=OFF"
    "-DCMAKE_HIP_ARCHITECTURES=gfx1102"
    "-DSTRATA_BUILD_TESTS=OFF"
    "-DSTRATA_PORTABLE=ON"
  ];

  meta = with lib; {
    description = "Strata local AI inference engine built from source for AMD ROCm (gfx1102)";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
