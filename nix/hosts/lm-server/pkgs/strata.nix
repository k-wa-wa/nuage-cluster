{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc,
  glibc,
  rocmPackages,
}:

# Strata 0.2 推論エンジン (AMD ROCm / gfx1102 向け)
# 公式の rx7900 release アーカイブ (gfx1100, gfx1101, gfx1102 向けコードオブジェクト、
# hipblas / hipblaslt / rocblas ライブラリ同梱) を NixOS 上で実行可能にする derivation である。
stdenv.mkDerivation rec {
  pname = "strata";
  version = "0.2.6";

  src = fetchurl {
    url = "https://github.com/Niko1221/Strata/releases/download/v${version}/strata-engine-0.1.50-linux-x86_64-hip-rx7900.tar.gz";
    hash = "sha256-b+sRkdT3zMWnmvhxXMamMIR0v3PPyVDq1lAOK9r8Q28=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    gcc.cc.lib
    glibc
    rocmPackages.clr
  ];

  # 同梱の HIP/ROCm 共有ライブラリが $ORIGIN からロードされるよう RPATH を保持する
  appendRunpaths = [
    "$ORIGIN"
    "/run/opengl-driver/lib"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/strata
    cp -r * $out/lib/strata/
    ln -s $out/lib/strata/strata $out/bin/strata
    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata local AI inference engine for large MoE models on AMD ROCm (gfx1102)";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
