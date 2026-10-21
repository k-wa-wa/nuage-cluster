{ writers }:

# ジョブの投入・終了待ち・結果判定と、MVS 内の設定反映を行う CLI (mvsctl.py)
writers.writePython3Bin "mvsctl" {
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./mvsctl.py)
