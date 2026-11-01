{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  python3,
  gcc,
}:

let
  version = "0.2.6";
  engineVersion = "0.1.50";
  controlVersion = "0.1.51";

  pythonEnv = python3.withPackages (
    ps: with ps; [
      numpy
      regex
      jinja2
      pyyaml
      requests
      pillow
      psutil
    ]
  );
in
stdenv.mkDerivation {
  pname = "strata";
  inherit version;

  srcEngine = fetchurl {
    name = "strata-engine.tar.gz";
    url = "https://github.com/Niko1221/Strata/releases/download/v${version}/strata-engine-${engineVersion}-linux-x86_64-hip-rx7900.tar.gz";
    hash = "sha256-hGmNvzTdI1LAudm/43HRPiXLc5/ARwEiCWPqTf7jdu0=";
  };

  srcControl = fetchurl {
    name = "strata-control.tar.gz";
    url = "https://github.com/Niko1221/Strata/releases/download/v${version}/strata-control-${controlVersion}-linux-x86_64.tar.gz";
    hash = "sha256-OcBgJfnQkIAvlwCmzicffE2nZ/SAKNc4ng3cR/a6qcI=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    gcc.cc.lib
  ];

  # 同梱の HIP/ROCm 共有ライブラリが $ORIGIN からロードされるよう RPATH を追加する
  appendRunpaths = [
    "$ORIGIN"
    "/run/opengl-driver/lib"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/strata $out/share/strata

    mkdir -p engine-src control-src
    tar -xzf $srcEngine -C engine-src
    tar -xzf $srcControl -C control-src
    rm -rf control-src/python

    # エンジンバイナリと ROCm ライブラリ群
    cp -r engine-src/* $out/lib/strata/
    ln -s $out/lib/strata/strata $out/bin/strata

    # コントロールプレーン (Python スクリプト、tools、data 等)
    cp -r control-src/* $out/share/strata/

    # OpenAI 互換 API サーバー起動ラッパー
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/strata-server \
      --add-flags "$out/share/strata/serve/server.py" \
      --set PYTHONPATH "$out/share/strata"

    # Pack 作成ツールラッパー (IQ2_XS 等の pack 作成用)
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/strata-pack \
      --add-flags "$out/share/strata/tools/iq_pack.py" \
      --set PYTHONPATH "$out/share/strata"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Strata local AI inference engine and OpenAI-compatible API server for AMD ROCm (gfx1102)";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
