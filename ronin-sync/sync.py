"""Back the vault up to its own PRIVATE git remote, and pull extra repos down.

Run by Task Scheduler every 30 minutes (install.ps1 -RegisterTasks sets that up).
Vault: commits any local change, pulls (rebase) whatever another machine or a
cloud job wrote, pushes. The remote is whatever `origin` the vault repo has;
set it once yourself (see README, "Vault backup"). No origin -> local commits only.
Extra repos (config.json -> sync.extra_pull_repos, paths): fast-forward pull only.
Silent; everything goes to data/sync.log next to this file.

The vault is your memory and holds personal data: only ever push it to a
PRIVATE repository.
"""
import datetime
import json
import os
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LOG = HERE / "data" / "sync.log"
NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW


def load_config():
    try:
        return json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


CFG = load_config()
VAULT = pathlib.Path(os.path.expandvars(CFG.get("vault_path", r"%USERPROFILE%\RONIN-memory")))
EXTRA = [pathlib.Path(os.path.expandvars(p)) for p in CFG.get("sync", {}).get("extra_pull_repos", [])]


def log(msg):
    LOG.parent.mkdir(exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{stamp} {msg}\n")


def git(*args, cwd=VAULT):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", creationflags=NO_WINDOW)
    return r.returncode, (r.stdout + r.stderr).strip()


def sync_vault():
    if not (VAULT / ".git").exists():
        log(f"vault is not a git repo yet ({VAULT}); run: git init in the vault")
        return
    git("add", "-A")
    if git("diff", "--cached", "--quiet")[0] != 0:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        code, out = git("commit", "-q", "-m", f"Vault sync {stamp}")
        if code:
            log(f"commit failed: {out}")
            return
    if not git("remote")[1].strip():
        log("ok (no remote configured, local commit only)")
        return
    code, out = git("pull", "--rebase", "-q")
    if code:
        git("rebase", "--abort")
        log(f"pull failed (local copy untouched): {out}")
        return
    code, out = git("push", "-q")
    if code:
        log(f"push failed: {out}")
        return
    log(f"ok {git('rev-parse', '--short', 'HEAD')[1]}")


def pull_extra():
    for repo in EXTRA:
        if not (repo / ".git").exists():
            continue
        code, out = git("pull", "--ff-only", "-q", cwd=repo)
        if code:
            log(f"{repo.name}: pull failed (local copy untouched): {out}")


if __name__ == "__main__":
    for step in (sync_vault, pull_extra):
        try:
            step()
        except Exception as e:  # never die silently
            log(f"error in {step.__name__}: {e!r}")
