# lm-server の llama-server に対して課題を走らせる。orc.chat (OpenRouter) だけを差し替え、課題と検証は run_all.py を使う。
# LoRA を比べるときは、llama-server を --lora <アダプタ> --lora-init-without-apply 付きで起動しておく。
# 結果は ../results-local-<日時>.jsonl に、呼び出しごとの記録は ../calls-local-<日時>.jsonl に書く。
import json, os, sys, time, urllib.error, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
import orc

URL = os.environ.get("LLAMA_URL", "http://192.168.5.222:8080")
# 設定名 -> (LoRA の scale, enable_thinking)。scale が None のときは lora を送らない (LoRA を読み込んでいないサーバー向け)
CFG = {"base-think": (0, True), "base-nothink": (0, False), "pi-nothink": (1, False), "pi-think": (1, True),
       "base-think-nolora": (None, True), "base-nothink-nolora": (None, False)}


def post(path, body, timeout):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def chat(model, messages, tools=None, max_tokens=8000, temperature=0.6, timeout=3600, extra=None):
    scale, think = CFG[model]
    body = {"model": "qwen3.8-27b", "messages": messages, "max_tokens": max_tokens, "temperature": temperature,
            "chat_template_kwargs": {"enable_thinking": think}}
    if scale is not None:
        body["lora"] = [{"id": 0, "scale": scale}]
    if tools:
        body["tools"] = tools
    t = time.time()
    try:
        # 手元の GPU は遅く、思考ありの長い出力は 600 秒を超えるため、待ち時間を 1 時間まで延ばす
        d = post("/v1/chat/completions", body, max(timeout, 3600))
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode()[:500]}")
    d["_elapsed"] = time.time() - t
    # llama-server の usage には思考の分が無いので、reasoning_content をトークン化して数える
    rc = d["choices"][0]["message"].get("reasoning_content") or ""
    n = len(post("/tokenize", {"content": rc}, 60).get("tokens", [])) if rc else 0
    u = d.setdefault("usage", {})
    u["completion_tokens_details"] = {"reasoning_tokens": n}
    tm = d.get("timings", {})
    LOG.write(json.dumps({"model": model, "prompt_tokens": u.get("prompt_tokens"), "completion_tokens": u.get("completion_tokens"),
                          "reasoning_tokens": n, "prompt_ms": tm.get("prompt_ms"), "predicted_ms": tm.get("predicted_ms"),
                          "draft_n": tm.get("draft_n"), "draft_n_accepted": tm.get("draft_n_accepted"),
                          "elapsed": d["_elapsed"], "finish": d["choices"][0].get("finish_reason")}) + "\n")
    LOG.flush()
    return d


orc.chat = chat
import run_all  # noqa: E402  (orc.chat を差し替えてから import する)

STAMP = time.strftime("%Y%m%d-%H%M%S")
OUTDIR = os.path.join(os.path.dirname(__file__), "..")
run_all.OUT = os.path.join(OUTDIR, "results-local-%s.jsonl" % STAMP)
LOG = open(os.path.join(OUTDIR, "calls-local-%s.jsonl" % STAMP), "a")

if __name__ == "__main__":
    configs = sys.argv[1].split(",")
    plan = [("agent", "A1", 1), ("agent", "A2", 1), ("agent", "A3", 1), ("single", "L1", 1), ("single", "L2", 1),
            ("single", "J1", 1), ("single", "J1", 2), ("single", "J1", 3), ("single", "E1", 1), ("single", "E1", 2)]
    if len(sys.argv) > 2:
        plan = [p for p in plan if p[1] in sys.argv[2].split(",")]
    print("OUT", run_all.OUT, flush=True)
    # llama-server は --parallel 1 なので、1 件ずつ順に投げる。設定を課題ごとに交互に回す
    for kind, tid, rep in plan:
        for c in configs:
            run_all.job((kind, c, tid, rep))
