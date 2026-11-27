{
  lib,
  stdenv,
  buildGo127Module,
  fetchFromGitHub,
  go_1_27,
}:

buildGo127Module (finalAttrs: {
  pname = "spiffe-helper";
  version = "0.12.4";

  src = fetchFromGitHub {
    owner = "spiffe";
    repo = "spiffe-helper";
    tag = "v${finalAttrs.version}";
    hash = "sha256-iglwZAc90r9VJ3BoYAsK0fmvikCJrj4301vJt/jaqzQ=";
  };

  # nixos-26.05 の go_1_27 (1.27.1) で v0.12.4 の go.mod (go 1.27.4) をビルド可能にする。
  # 言語機能・依存ともに 1.27.1 で全単体テストが通ることを確認済み。
  # 併せて並行読み取り中のアトミック置換回帰テストを組み込む。
  postPatch = ''
    substituteInPlace go.mod --replace-fail "go 1.27.4" "go ${go_1_27.version}"
    cp ${./write_atomic_test.go} pkg/disk/write_atomic_test.go
  '';

  vendorHash = "sha256-ZCCh+eE8SqT/0kKlUeLQOXXGU/pfESpTpnHuQEu2cZI=";

  ldflags = [
    "-s"
    "-w"
  ];

  preCheck = ''
    patchShebangs pkg/sidecar/sidecar_test.sh
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/${finalAttrs.meta.mainProgram} -h
    runHook postInstallCheck
  '';

  meta = {
    description = "Retrieve and manage SVIDs on behalf of a workload";
    homepage = "https://github.com/spiffe/spiffe-helper";
    license = lib.licenses.asl20;
    mainProgram = "spiffe-helper";
  };
})
