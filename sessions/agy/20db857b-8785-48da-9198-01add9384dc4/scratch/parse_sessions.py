import json
import os
import re

brain_dir = "/home/koby/.gemini/antigravity-cli/brain"
sessions = []

for conv_id in os.listdir(brain_dir):
    full_path = os.path.join(brain_dir, conv_id)
    if not os.path.isdir(full_path):
        continue
    transcript_path = os.path.join(full_path, ".system_generated", "logs", "transcript.jsonl")
    if not os.path.exists(transcript_path):
        continue

    first_time = None
    last_time = None
    user_prompts = []

    with open(transcript_path, "r", encoding="utf-8") as f:
        for line in f:
            try:
                data = json.loads(line)
                t = data.get("created_at")
                if t:
                    if not first_time:
                        first_time = t
                    last_time = t
                if data.get("type") == "USER_INPUT":
                    content = data.get("content", "")
                    m = re.search(r"<USER_REQUEST>(.*?)</USER_REQUEST>", content, re.DOTALL)
                    if m:
                        req = m.group(1).strip()
                    else:
                        req = content.strip()
                    if req:
                        user_prompts.append(req)
            except Exception:
                pass

    artifacts = [f for f in os.listdir(full_path) if f.endswith(".md")]

    sessions.append({
        "id": conv_id,
        "start": first_time,
        "end": last_time,
        "prompt_count": len(user_prompts),
        "first_prompt": user_prompts[0] if user_prompts else "N/A",
        "all_prompts": user_prompts,
        "artifacts": artifacts,
    })

sessions.sort(key=lambda s: s["start"] or "")

for i, s in enumerate(sessions, 1):
    cid = s['id']
    start = s['start']
    end = s['end']
    count = s['prompt_count']
    arts = s['artifacts']
    print(f"=== Session {i}: {cid} ===")
    print(f"Time: {start} -> {end} (User prompts: {count})")
    print(f"Artifacts: {arts}")
    print("Initial request:")
    first = s['first_prompt'][:300].replace('\n', '\n  ')
    print(f"  {first}")
    if len(s['all_prompts']) > 1:
        print("Sample follow-up requests:")
        for p in s['all_prompts'][1:6]:
            print(f"  - {p[:150]}")
    print()
