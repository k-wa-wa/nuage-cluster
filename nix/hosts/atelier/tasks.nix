# atelier 上で定期実行する自律タスク (programs.autopilot5.tasks) を定義する。
{
  lib,
  pkgs,
  ...
}:

let
  targetRepos = [
    "k-wa-wa/nuage-cluster"
    "k-wa-wa/nuage-autopilot5"
    "k-wa-wa/nuage-monitoring-stack"
    "k-wa-wa/pechka"
    "k-wa-wa/bare-web-proxy"
    "k-wa-wa/nuage-usage-ledger"
  ];

  # セッション枠・同時稼働数・着手可能な Issue の有無を判定し、
  # すべて満たすときだけ exit 0 を返して LLM 起動へ進める。
  checkIssueHunterSlot = pkgs.writeShellApplication {
    name = "check-issue-hunter-slot";
    runtimeInputs = with pkgs; [
      gh
      jq
    ];
    text = ''
      # 1. 同時稼働中のワークツリー数チェック
      ps_json=$(orca worktree ps --json)
      working_count=$(printf '%s' "$ps_json" | jq -r '
        if .ok != true then error("orca worktree ps failed") end
        | [.result.worktrees[]? | select(.status == "working")] | length
      ')
      if [ "$working_count" -ge 1 ]; then
        echo "skip: 稼働中のワークツリーが ''${working_count} 件ある" >&2
        exit 1
      fi

      # 2. セッション枠の余裕チェック
      # 実装役 (models.yaml の roles.impl 先頭: antigravity) と
      # レビュー役 (models.yaml の roles.review 先頭: claude) の両方について、
      # 1 タスク完走に必要な余裕を残すため 5 時間セッション枠 50% 未満・週間枠 70% 未満を条件とする。
      # 将来リセット時刻 (session.resetsAt / weekly.resetsAt) 直前の緩和条件等を
      # 追加しやすいよう閾値を分離して判定する。
      SESSION_MAX_USED_PERCENT=50
      WEEKLY_MAX_USED_PERCENT=70

      account_json=$(orca account list --json)
      if ! printf '%s' "$account_json" | jq -e \
        --argjson session_max "$SESSION_MAX_USED_PERCENT" \
        --argjson weekly_max "$WEEKLY_MAX_USED_PERCENT" '
        def provider_has_headroom($p):
          ($p != null)
          and ($p.status == "ok")
          and (($p.session.usedPercent | type) == "number")
          and ($p.session.usedPercent < $session_max)
          and (($p.weekly.usedPercent | type) == "number")
          and ($p.weekly.usedPercent < $weekly_max);

        (.ok == true)
        and provider_has_headroom(.result.rateLimits.antigravity)
        and provider_has_headroom(.result.rateLimits.claude)
      ' >/dev/null; then
        echo "skip: セッション枠の余裕が不足している (antigravity / claude)" >&2
        exit 1
      fi

      # 3. 候補 Issue の存在チェック
      worktrees_json=$(orca worktree list --json)
      if ! printf '%s' "$worktrees_json" | jq -e '.ok == true' >/dev/null; then
        echo "skip: orca worktree list --json の取得に失敗した" >&2
        exit 1
      fi

      repos=(
        ${lib.concatMapStringsSep "\n        " (r: ''"${r}"'') targetRepos}
      )

      for repo in "''${repos[@]}"; do
        if ! issues_json=$(gh issue list -R "$repo" --state open --limit 30 --json number,author,labels); then
          echo "warn: gh issue list failed for $repo" >&2
          continue
        fi
        if printf '%s' "$issues_json" | jq -e --arg repo "$repo" --argjson wt "$worktrees_json" '
          ($wt.result.worktrees // []) as $worktrees
          | ($repo | split("/")[1]) as $repo_name
          | [
              $worktrees[]
              | select(
                  (.projectId == ("github:" + $repo))
                  or ((.projectId == null) and ((.path // "") | split("/") | index($repo_name) != null))
                )
              | (
                  (
                    .linkedIssue
                    | if type == "number" then .
                      elif type == "string" then (tonumber? // empty)
                      elif type == "object" then (.number // empty)
                      else empty
                      end
                  ),
                  (.linkedItems[]? | select(.type == "issue") | .number // empty)
                )
            ] as $linked_issues
          | any(
              .[];
              (.author.login == "k-wa-wa")
              and (
                [.labels[]?.name]
                | any(. == "manual" or . == "blocked" or . == "wontfix" or . == "autopilot-skip")
                | not
              )
              and (.number as $n | any($linked_issues[]; . == $n) | not)
            )
        ' >/dev/null; then
          exit 0
        fi
      done

      echo "skip: 着手可能な候補 Issue が無い" >&2
      exit 1
    '';
  };
in
{
  programs.autopilot5 = {
    taskDefaults = {
      envFile = "/var/lib/atelier/secrets.env";
      memoryRepo = "/home/nixos/ghq/github.com/k-wa-wa/atelier-memory";
    };

    tasks.issue-hunter = {
      soul = ./tasks/issue-hunter/SOUL.md;
      # 選定・引き継ぎの窓口役。実装・レビュー本体は autopilot-run 側が models.yaml に従って動かす。
      agent = "agy";
      level = "standard";
      trigger = {
        type = "cron";
        schedule = "*:0/30";
      };
      precheck = {
        command = "${checkIssueHunterSlot}/bin/check-issue-hunter-slot";
        timeoutSec = 45;
      };
      # autopilot-task の snapshotWorkdir が不要な走査をしないよう、専用ディレクトリを自動利用させる。
      workdir = null;
      # autopilot-run --from spec の完走を待つため 2 時間とする。
      timeoutSec = 7200;
      memory = {
        file = "issue-hunter/MEMORY.md";
        maxLines = 200;
      };
    };
  };
}
