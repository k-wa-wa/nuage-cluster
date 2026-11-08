import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from orc import chat
from tasks import REPO
BAN=re.compile(r"(secret|sops|kubeconfig|\.env|login-keys|\.pem|id_)", re.I)
# 評価自体の資材 (過去の回答を含む) はモデルに読ませない
SELF="docs/ideas/strata/api-comparison/"
FILES=[f for f in subprocess.run(["git","-C",REPO,"ls-files"],capture_output=True,text=True,check=True).stdout.split("\n") if f and not BAN.search(f) and not f.startswith(SELF)]
FSET=set(FILES)
def list_dir(path=""):
    p=path.strip("/"); pre=(p+"/") if p else ""
    out=sorted({f[len(pre):].split("/")[0]+("/" if "/" in f[len(pre):] else "") for f in FILES if f.startswith(pre)})
    return "\n".join(out) or "(not found)"
def grep(pattern, path=""):
    p=path.strip("/")
    tgt=[f for f in FILES if f.startswith(p)] if p else FILES
    try: rx=re.compile(pattern)
    except re.error as e: return f"invalid regex: {e}"
    hits=[]
    for f in tgt:
        try:
            for i,l in enumerate(open(os.path.join(REPO,f),errors="replace"),1):
                if rx.search(l): hits.append(f"{f}:{i}:{l.rstrip()[:200]}")
        except (IsADirectoryError,FileNotFoundError): pass
        if len(hits)>=60: break
    return "\n".join(hits[:60]) or "(no match)"
def read_file(path, start=1, end=200):
    p=path.strip("/")
    if p not in FSET: return "(not found or not allowed)"
    lines=open(os.path.join(REPO,p),errors="replace").read().split("\n")
    start=max(1,int(start)); end=min(len(lines),int(end),start+299)
    return "\n".join(f"{i}\t{lines[i-1]}" for i in range(start,end+1))
TOOLS=[
 {"type":"function","function":{"name":"list_dir","description":"リポジトリ内のディレクトリの中身を一覧する","parameters":{"type":"object","properties":{"path":{"type":"string","description":"リポジトリルートからの相対パス。空ならルート"}}}}},
 {"type":"function","function":{"name":"grep","description":"正規表現で行を検索する (最大 60 件)","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string","description":"検索を絞るパスの接頭辞"}},"required":["pattern"]}}},
 {"type":"function","function":{"name":"read_file","description":"ファイルを行番号付きで読む (一度に最大 300 行)","parameters":{"type":"object","properties":{"path":{"type":"string"},"start":{"type":"integer"},"end":{"type":"integer"}},"required":["path"]}}},
]
FN={"list_dir":list_dir,"grep":grep,"read_file":read_file}
SYS="あなたはインフラリポジトリ (NixOS / Kubernetes / Terraform) の調査役である。ツールでリポジトリを読み、根拠となるファイルパスと行番号を添えて日本語で簡潔に答える。推測で埋めない。"
def run(model, question, max_steps=15):
    msgs=[{"role":"system","content":SYS},{"role":"user","content":question}]
    st={"model":model,"steps":0,"tool_calls":0,"prompt_tokens":0,"completion_tokens":0,"reasoning_tokens":0,"cost":0.0,"elapsed":0.0,"errors":[]}
    for step in range(max_steps):
        d=chat(model,msgs,tools=TOOLS,max_tokens=16000)
        u=d.get("usage",{}); st["steps"]+=1
        st["prompt_tokens"]+=u.get("prompt_tokens",0); st["completion_tokens"]+=u.get("completion_tokens",0)
        st["reasoning_tokens"]+=(u.get("completion_tokens_details") or {}).get("reasoning_tokens",0) or 0
        st["cost"]+=u.get("cost",0) or 0; st["elapsed"]+=d["_elapsed"]
        ch=d["choices"][0]; m=ch["message"]
        if ch.get("finish_reason")=="length": st["errors"].append("length")
        msgs.append({k:v for k,v in m.items() if k in("role","content","tool_calls")})
        tcs=m.get("tool_calls") or []
        if not tcs:
            st["answer"]=m.get("content"); return st
        for tc in tcs:
            st["tool_calls"]+=1
            try:
                args=json.loads(tc["function"]["arguments"] or "{}")
                res=FN[tc["function"]["name"]](**args)
            except Exception as e:
                res=f"tool error: {e}"; st["errors"].append(f"tool:{tc['function']['name']}:{e}")
            msgs.append({"role":"tool","tool_call_id":tc["id"],"content":res[:12000]})
    st["answer"]=None; st["errors"].append("max_steps"); return st
if __name__=="__main__":
    model, qid, q, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    st=run(model,q); st["qid"]=qid
    with open(out,"a") as f: f.write(json.dumps(st,ensure_ascii=False)+"\n")
    print(qid, model, "steps",st["steps"],"tools",st["tool_calls"],"reason_tok",st["reasoning_tokens"],"cost %.4f"%st["cost"],"%.0fs"%st["elapsed"],st["errors"])
