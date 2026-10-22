{
  pkgs,
  lib,
  cicerone3270,
  mainframeApps,
  ...
}:

# 3270 端末の案内 (cicerone3270)。ssh -t mainframe ci3270 で TSO を案内付きで操作する。
# cicerone3270 は汎用のツールで、組み込みの辞書は MVS/CE の一般的な内容だけを持つ。
# ここで基盤の辞書 (./guide) と業務アプリの辞書 (各アプリの出力の cicerone3270/) を足して起動する。
# 辞書は先に並べたものほど優先され、どれも組み込みの辞書より優先される。

let
  guidePath = lib.concatStringsSep ":" (
    [ "${./guide}" ] ++ map (app: "${app}/cicerone3270") mainframeApps
  );
  ci3270 = pkgs.writeShellApplication {
    name = "ci3270";
    text = ''
      # 辞書を持たないアプリのディレクトリは ci3270 が無視する
      export CI3270_GUIDE_PATH="${guidePath}''${CI3270_GUIDE_PATH:+:$CI3270_GUIDE_PATH}"
      exec ${lib.getExe cicerone3270} "$@"
    '';
  };
in
{
  environment.systemPackages = [ ci3270 ];
}
