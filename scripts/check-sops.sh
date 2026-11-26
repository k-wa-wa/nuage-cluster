#!/usr/bin/env bash
# SOPS 管理対象ファイルが暗号化済みであるかと、.sops.yaml の creation_rules に
# 登録されているかを読み取り専用で検証する。復号や編集は一切行わない。

set -euo pipefail

exec python3 - "$@" <<'PY'
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

EXCLUDED_DIRS = {
    ".git",
    ".terragrunt-cache",
    ".terraform",
    ".autopilot",
    "node_modules",
}
TARGET_PREFIXES = ("nix/", "terraform/", "manifests/")


def resolve_default_root() -> Path:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return Path.cwd()


def load_path_regexes(sops_yaml: Path) -> list[re.Pattern[str]]:
    if not sops_yaml.is_file():
        raise RuntimeError(f".sops.yaml が見つからない: {sops_yaml}")

    patterns: list[re.Pattern[str]] = []
    in_creation_rules = False

    for raw_line in sops_yaml.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped == "---":
            continue

        if not raw_line[0].isspace():
            if re.match(r"^creation_rules:\s*(?:#.*)?$", raw_line):
                in_creation_rules = True
            else:
                in_creation_rules = False
            continue

        if not in_creation_rules:
            continue

        m = re.match(r"^\s*(?:-\s*)?path_regex:\s*(.+)$", raw_line)
        if not m:
            continue

        val = m.group(1).strip()
        if (val.startswith('"') and val.endswith('"')) or (
            val.startswith("'") and val.endswith("'")
        ):
            val = val[1:-1]
        else:
            val = re.sub(r"\s+#.*$", "", val).strip()

        patterns.append(re.compile(val))

    if not patterns:
        raise RuntimeError(".sops.yaml に creation_rules[].path_regex が定義されていない")

    return patterns


def collect_targets(root: Path, regexes: list[re.Pattern[str]]) -> list[Path]:
    targets: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = Path(dirpath).relative_to(root)
        # 除外ディレクトリおよびリポジトリ直下の docs/ を走査対象から外す
        pruned: list[str] = []
        for d in sorted(dirnames):
            if d in EXCLUDED_DIRS:
                continue
            if rel_dir == Path(".") and d == "docs":
                continue
            pruned.append(d)
        dirnames[:] = pruned

        for fname in sorted(filenames):
            if fname.endswith(".example"):
                continue
            full_path = Path(dirpath) / fname
            rel_posix = full_path.relative_to(root).as_posix()

            matched_rule = any(rx.search(rel_posix) for rx in regexes)
            is_secrets_yaml = (
                rel_posix.startswith(TARGET_PREFIXES) and fname == "secrets.yaml"
            )
            if matched_rule or is_secrets_yaml:
                targets.append(full_path)

    return targets


EMPTY_YAML_VALUES = {"", "null", "~", '""', "''", "{}", "[]"}


def inspect_sops_file(path: Path) -> list[str]:
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return ["UTF-8 として読み取れない"]

    if not content.strip():
        return ["ファイルが空である"]

    in_sops_block = False
    has_sops_block = False
    has_mac = False
    plaintext_lines: list[int] = []

    for lineno, raw_line in enumerate(content.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped in ("---", "..."):
            continue

        if not raw_line[0].isspace():
            if re.match(r"^sops:\s*(?:#.*)?$", raw_line):
                in_sops_block = True
                has_sops_block = True
                continue
            in_sops_block = False

        if in_sops_block:
            if re.match(r"^\s+mac:\s*['\"]?ENC\[", raw_line):
                has_mac = True
            continue

        # リスト要素で値自体が ENC[...] の場合 (例: "  - ENC[...]")
        if re.match(r"^\s*-\s+['\"]?ENC\[", raw_line):
            continue

        # sops ブロック外では、空値および親キーを除きすべての値が ENC[ で始まる必要がある
        m_kv = re.match(
            r'^\s*(?:-\s+)?(?:"[^"]+"|\'[^\']+\'|[^:#\s\[][^:#\[]*):\s*(.*)$',
            raw_line,
        )
        if m_kv:
            val = m_kv.group(1).strip()
            if val.startswith("#"):
                continue
            if val not in EMPTY_YAML_VALUES and not re.match(r"^['\"]?ENC\[", val):
                plaintext_lines.append(lineno)
            continue

        m_li = re.match(r"^\s*-\s*(.*)$", raw_line)
        if m_li:
            val = m_li.group(1).strip()
            if val.startswith("#"):
                continue
            if val not in EMPTY_YAML_VALUES and not re.match(r"^['\"]?ENC\[", val):
                plaintext_lines.append(lineno)
            continue

        plaintext_lines.append(lineno)

    errors: list[str] = []
    if not (has_sops_block and has_mac):
        errors.append("SOPS 暗号化メタデータ (sops: / mac: ENC[) が見つからない")
    if plaintext_lines:
        lines_str = ", ".join(str(n) for n in plaintext_lines[:5])
        if len(plaintext_lines) > 5:
            lines_str += ", ..."
        errors.append(f"sops ブロック外に未暗号化の値がある (line {lines_str})")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="SOPS 管理対象ファイルの暗号化状態と .sops.yaml 登録を検査する"
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="検査対象リポジトリのルートディレクトリ",
    )
    args = parser.parse_args()

    root = (args.root if args.root is not None else resolve_default_root()).resolve()
    sops_yaml = root / ".sops.yaml"

    try:
        regexes = load_path_regexes(sops_yaml)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    targets = collect_targets(root, regexes)
    if not targets:
        print("[ERROR] 検査対象の SOPS ファイルが 0 件である", file=sys.stderr)
        return 1

    failed = False
    for path in targets:
        rel = path.relative_to(root).as_posix()
        errors: list[str] = []

        if not any(rx.search(rel) for rx in regexes):
            errors.append(".sops.yaml の creation_rules に一致しない")

        errors.extend(inspect_sops_file(path))

        if errors:
            failed = True
            print(f"[FAIL] {rel}: {'; '.join(errors)}")
        else:
            print(f"[PASS] {rel}")

    if failed:
        print(f"SOPS check failed ({len(targets)} files checked).", file=sys.stderr)
        return 1

    print(f"All SOPS checks passed ({len(targets)} files checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
