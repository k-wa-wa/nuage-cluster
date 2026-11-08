import json, os, sys, time, urllib.request, urllib.error, re
sys.path.insert(0, os.path.dirname(__file__))
from tasks import REPO
# OpenRouter の API キーは環境変数 API_KEY か、リポジトリルートの .env (git 管理外) の API_KEY= から読む
ENV=os.path.join(REPO, ".env")
def key():
    if os.environ.get("API_KEY"): return os.environ["API_KEY"]
    if not os.path.exists(ENV): raise SystemExit("API_KEY is not set and .env not found")
    for l in open(ENV):
        if l.startswith("API_KEY="):
            v=l.split("=",1)[1].strip().strip('"').strip("'")
            if not v: raise SystemExit("API_KEY is empty")
            return v
    raise SystemExit("API_KEY not found")
def chat(model, messages, tools=None, max_tokens=8000, temperature=0.6, timeout=600, extra=None):
    body={"model":model,"messages":messages,"max_tokens":max_tokens,"temperature":temperature,"usage":{"include":True}}
    if tools: body["tools"]=tools
    if extra: body.update(extra)
    req=urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",data=json.dumps(body).encode(),
        headers={"Authorization":"Bearer "+key(),"Content-Type":"application/json","X-Title":"nuage-eval"})
    t=time.time()
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r: d=json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode()[:500]}")
    d["_elapsed"]=time.time()-t
    return d
