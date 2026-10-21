"""帳票プリンタ (プリンタ 2, 出力クラス M) の印字を PDF にする。

MVS の帳票プリンタは /var/lib/mainframe/printers/prt00f.txt に追記されていく。
このプログラムは、前回読んだ位置から先に「START JOB n 名前」から「END JOB n 名前」までの
出力が 1 本揃っていれば、それを連続帳票紙を模した PDF にする。揃っていない出力は次回に回す。

systemd.path で prt00f.txt の更新を契機に起動される (時刻は持たない)。
PDF は tmpfs (/run/mainframe-printer) に置き、永続化しない。
"""

import argparse
import datetime as dt
import os
import re
from pathlib import Path

PRINTER = Path(os.environ.get("MVS_STATE_DIR", "/var/lib/mainframe")) / "printers" / "prt00f.txt"
START_RE = re.compile(r"\*\*\*\*M\s+START\s+JOB\s+(\d+)\s+(\S+)\s")


def outputs(text):
    """text 中の完結した出力を (ジョブ番号, ジョブ名, 本文, 終端位置) で返す"""
    pos = 0
    while True:
        start = START_RE.search(text, pos)
        if not start:
            return
        jobno, jobname = start.groups()
        end = re.search(rf"\*\*\*\*M\s+END\s+JOB\s+{jobno}\s+{re.escape(jobname)}\s.*\n?", text[start.end():])
        if not end:
            return
        body = text[start.end(): start.end() + end.start()]
        # 先頭のバナーページの残り (START 行の行末まで) と、末尾のバナーページを落とす
        if "\f" in body:
            body = body[body.index("\f") + 1:]
            body = body[: body.rindex("\f")] if "\f" in body else body
        yield jobno, jobname, body.replace("\r", ""), start.end() + end.end()
        pos = start.end() + end.end()


def render_pdf(text, path):
    """連続帳票紙 (14 7/8 x 11 インチ、6 行/インチ、10 字/インチ) を模した PDF にする"""
    from reportlab.lib.colors import Color, white
    from reportlab.pdfgen import canvas

    inch = 72
    width, height = 14.875 * inch, 11 * inch
    margin = 0.75 * inch  # 両端の送り穴の帯
    line_h = inch / 6
    lines_per_page = 66
    top = height - 0.25 * inch
    green = Color(0.82, 0.93, 0.82)

    c = canvas.Canvas(str(path), pagesize=(width, height))
    pages = [p.split("\n") for p in text.split("\f")]
    pages = [p for p in pages if any(line.strip() for line in p)] or [[""]]
    for page in pages:
        # 3 行ごとに緑と白の帯を交互に敷く
        for band in range(0, lines_per_page, 6):
            c.setFillColor(green)
            c.rect(margin, top - (band + 3) * line_h, width - 2 * margin, 3 * line_h, stroke=0, fill=1)
        # 送り穴
        c.setFillColor(white)
        c.setStrokeColor(Color(0.7, 0.7, 0.7))
        for i in range(22):
            y = height - (i + 0.5) * 0.5 * inch
            for x in (0.375 * inch, width - 0.375 * inch):
                c.circle(x, y, 0.08 * inch, stroke=1, fill=1)
        c.setFillColor(Color(0.1, 0.1, 0.1))
        c.setFont("Courier", 12)  # Courier 12pt は 1 字 7.2pt = 10 字/インチ
        for i, line in enumerate(page[:lines_per_page]):
            c.drawString(margin + 0.25 * inch, top - (i + 0.8) * line_h, line)
        c.showPage()
    c.save()


def main():
    parser = argparse.ArgumentParser(prog="mainframe-printer")
    parser.add_argument("--out-dir", default="/run/mainframe-printer")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    state = out_dir / ".offset"

    if not PRINTER.exists():
        return
    offset = int(state.read_text()) if state.exists() else 0
    size = PRINTER.stat().st_size
    if size < offset:
        # 稼働中にプリンタ出力が空にされた
        offset = 0
    with PRINTER.open("rb") as f:
        f.seek(offset)
        text = f.read().decode("ascii", errors="replace")

    consumed = 0
    for jobno, jobname, body, end in outputs(text):
        # 帳票に対象日があればそれを、無ければ処理時刻をファイル名に使う
        m = re.search(r"USAGE DATE: (\d{4}-\d{2}-\d{2})", body)
        stamp = m.group(1) if m else dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = out_dir / f"{jobname}-{stamp}.pdf"
        render_pdf(body, path)
        print(f"JOB {jobno} {jobname}: {path}")
        consumed = end
    # 文字列の位置とバイト位置は ASCII なので一致する
    state.write_text(str(offset + consumed))


if __name__ == "__main__":
    main()
