"""システムの MVS 設定 (mvs-config/) に、業務アプリの資材を合成する。mvs-config.nix から呼ぶ。

    compose_mvs_config.py <出力先> <システムの設定> <アプリの資材>...

アプリの資材 (各アプリの flake の packages.default):
  members/<データセット名>/<メンバー名>  そのまま加える
  schedule                              ZTIMER の予定表 (SYS2.CONTROL(ZTIMER)) の末尾に足す
  rakf                                  RAKF の権限 (SYS1.SECURE.CNTL(PROFILES)) に足す行 (任意)
"""

import shutil
import sys
from pathlib import Path


def writable(root):
    """store からコピーしたものは読み取り専用なので、書き込めるようにする"""
    root.chmod(0o755)
    for p in root.rglob("*"):
        p.chmod(0o755 if p.is_dir() else 0o644)


def main(out, base, apps):
    out, base = Path(out), Path(base)
    shutil.copytree(base, out)
    writable(out)

    ztimer = out / "SYS2.CONTROL" / "ZTIMER"
    profiles = out / "SYS1.SECURE.CNTL" / "PROFILES"
    rakf_lines = profiles.read_text().splitlines()
    for app in map(Path, apps):
        shutil.copytree(app / "members", out, dirs_exist_ok=True)
        writable(out)
        with ztimer.open("a") as f:
            f.write((app / "schedule").read_text())
        if (app / "rakf").exists():
            rakf_lines += (app / "rakf").read_text().splitlines()
    # 予定表の末尾をコメント行で閉じる (MVS/CE の既定の形に合わせる)
    with ztimer.open("a") as f:
        f.write("*\n")
    # RAKF の権限表は EBCDIC の照合順に並んでいる (MVS/CE の既定のファイルもこの順)。
    # 足した行もこの順に差し込む
    rakf_lines = sorted(set(rakf_lines), key=lambda line: line.encode("cp037"))
    profiles.write_text("\n".join(rakf_lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
