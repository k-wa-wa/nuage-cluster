# KICKS for TSO 1.5.0 の配布物。CICS を真似たトランザクション処理で、作者は Mike Noel。
# http://www.kicksfortso.com/
#
# ライセンスにより、KICKS の資材 (個々のオブジェクト) は公開のリポジトリに置けない。
# そのため Git には持たず、元の配布物 (kicks-tso-v1r5m0.zip) をそのまま取得し、
# 導入に使う XMI (TSO の XMIT 形式) とライセンス文だけを取り出す。
# MVS への導入は mvs-config (mvsctl apply-config --kicks-xmi) が行う。
{
  runCommand,
  fetchurl,
  unzip,
}:

let
  version = "1.5.0";
  # moshix/kicks が元の配布物をそのまま置いている。コミットで固定する
  src = fetchurl {
    url = "https://raw.githubusercontent.com/moshix/kicks/d2fa27b17c659b9f3c9d3cf33442d43679f1337f/kicks-tso-v1r5m0.zip";
    hash = "sha256-4N8BvuGYjBxz27Ckngguiun9pYIqAvi5x5hYNWXBd/E=";
  };
in
# zip のディレクトリ項目が壊れていて unzip が全体の展開で警告 (終了コード 1) を出すため、必要なファイルだけを取り出す
runCommand "kicks-tso-${version}" { nativeBuildInputs = [ unzip ]; } ''
  mkdir -p $out
  unzip -p ${src} kicks-tso-v1r5m0/kicks-tso-v1r5m0.xmi > $out/kicks-tso-v1r5m0.xmi
  unzip -p ${src} kicks-tso-v1r5m0/kicks-license.txt > $out/kicks-license.txt
  # XMI は 80 バイトのカードの並び
  test $(( $(stat -c %s $out/kicks-tso-v1r5m0.xmi) % 80 )) -eq 0
''
