import json, os, re, subprocess, sys, tempfile, shutil, time
sys.path.insert(0, os.path.dirname(__file__))
from concurrent.futures import ThreadPoolExecutor
from orc import chat
import agent, tasks
# 実行ごとに別ファイルへ書く (保存済みの results.jsonl を上書きしない)
OUT=os.path.join(os.path.dirname(__file__),"..","results-%s.jsonl"%time.strftime("%Y%m%d-%H%M%S"))
MODELS=["qwen/qwen3.8-flash","qwen/qwen3.8-27b"]
def usage(d):
    u=d.get("usage",{})
    return {"prompt_tokens":u.get("prompt_tokens",0),"completion_tokens":u.get("completion_tokens",0),
            "reasoning_tokens":(u.get("completion_tokens_details") or {}).get("reasoning_tokens",0) or 0,
            "cost":u.get("cost",0) or 0,"elapsed":d["_elapsed"],"finish":d["choices"][0].get("finish_reason"),"provider":d.get("provider")}
def strip_fence(s):
    s=(s or "").strip()
    m=re.match(r"^```[a-zA-Z]*\n(.*?)\n?```$",s,re.S)
    return m.group(1) if m else s
def check_json(text):
    ids={a[0] for a in tasks.ARTICLES}
    try: o=json.loads(strip_fence(text))
    except Exception as e: return [f"json parse: {e}"]
    errs=[]
    sel=o.get("selected",[]); sc=o.get("script",[])
    sid=[x.get("id") for x in sel]
    if len(sel)!=4: errs.append(f"selected={len(sel)}")
    if len(set(sid))!=len(sid) or not set(sid)<=ids: errs.append(f"bad ids {sid}")
    for x in sel:
        if len(x.get("reason",""))>60: errs.append(f"reason len {len(x['reason'])}")
    if not 8<=len(sc)<=12: errs.append(f"script lines={len(sc)}")
    for i,l in enumerate(sc):
        if l.get("speaker")!=("A" if i%2==0 else "B"): errs.append(f"speaker order at {i}"); break
    for l in sc:
        if len(l.get("text",""))>80: errs.append(f"text len {len(l['text'])}")
        if l.get("ref") not in sid: errs.append(f"ref {l.get('ref')} not selected")
    if set(sid)-{l.get("ref") for l in sc}: errs.append("some selected never referenced")
    return errs or ["OK"], sorted(sid)
def check_diff(text):
    d=tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(d,os.path.dirname(tasks.E1_FILE)))
        shutil.copy(os.path.join(tasks.REPO,tasks.E1_FILE),os.path.join(d,tasks.E1_FILE))
        p=subprocess.run(["patch","-p1","--no-backup-if-mismatch","-r","-"],cwd=d,input=strip_fence(text)+"\n",capture_output=True,text=True)
        if p.returncode!=0: return ["patch failed: "+(p.stdout+p.stderr).strip()[-300:]]
        new=open(os.path.join(d,tasks.E1_FILE)).read()
        errs=[]
        if "65536" in new: errs.append("65536 remains")
        if '"32768"' not in new: errs.append("32768 missing")
        if new.count('"q8_0"')!=2: errs.append(f"q8_0 count {new.count(chr(34)+'q8_0'+chr(34))}")
        if '"q4_0"' in new: errs.append("q4_0 remains")
        diff=subprocess.run(["diff","-u",os.path.join(tasks.REPO,tasks.E1_FILE),os.path.join(d,tasks.E1_FILE)],capture_output=True,text=True).stdout
        changed=[l for l in diff.split("\n") if l[:1] in "+-" and not l.startswith(("+++","---"))]
        return (errs or ["OK"]), changed
    finally: shutil.rmtree(d)
def single(model, tid, prompt, checker=None):
    d=chat(model,[{"role":"user","content":prompt}],max_tokens=16000)
    m=d["choices"][0]["message"]; r={"qid":tid,"model":model,**usage(d),"answer":m.get("content")}
    if checker:
        try: r["check"]=checker(m.get("content"))
        except Exception as e: r["check"]=[f"checker error {e}"]
    return r
def job(spec, _retry=True):
    kind,model,tid,rep=spec
    try:
        if kind=="agent":
            r=agent.run(model,tasks.AGENT_Q[tid]); r["qid"]=tid
        elif tid=="L1": r=single(model,tid,tasks.L1)
        elif tid=="L2": r=single(model,tid,tasks.L2)
        elif tid=="J1": r=single(model,tid,tasks.J1,check_json)
        elif tid=="E1": r=single(model,tid,tasks.e1_prompt(),check_diff)
    except SystemExit as e: r={"qid":tid,"model":model,"fatal":str(e)}
    except Exception as e:
        if _retry and "timed out" in repr(e):
            print("retry",tid,rep,model,flush=True); return job(spec,False)
        r={"qid":tid,"model":model,"fatal":repr(e)}
    r["rep"]=rep
    with open(OUT,"a") as f: f.write(json.dumps(r,ensure_ascii=False)+"\n")
    print(tid,rep,model,{k:r.get(k) for k in ("steps","tool_calls","reasoning_tokens","completion_tokens","elapsed","check","errors","fatal")},flush=True)
if __name__=="__main__":
    specs=[]
    for a in sys.argv[1:]:
        kind,model,tid,rep=a.split(",")
        specs.append((kind,model,tid,int(rep)))
    with ThreadPoolExecutor(6) as ex: list(ex.map(job,specs))
