"""Test sync-ai-sessions.yml playbook behavior with isolated mock sessions and git repo."""

import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class SyncAiSessionsTest(unittest.TestCase):
    def test_playbook_syntax(self):
        """Ensure the playbook passes ansible-playbook --syntax-check."""
        playbook = REPO / "playbooks/sync-ai-sessions.yml"
        res = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", str(playbook), "--syntax-check"],
            text=True,
            capture_output=True,
            timeout=30,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_root_symlink_exists(self):
        """Ensure sync-ai-sessions.yml symlink exists at repo root."""
        symlink = REPO / "sync-ai-sessions.yml"
        self.assertTrue(symlink.is_symlink())
        self.assertEqual(symlink.resolve(), (REPO / "playbooks/sync-ai-sessions.yml").resolve())

    def test_sync_execution_and_filtering(self):
        """Test isolated session sync: directory creation, filtering, and index generation."""
        with tempfile.TemporaryDirectory(prefix="ai-sessions-test-") as temp_dir:
            temp_path = Path(temp_dir)
            fake_home = temp_path / "home"
            fake_repo = temp_path / "LINUX"
            fake_home.mkdir()
            fake_repo.mkdir()

            # Initialize a git repo in fake_repo
            subprocess.run(["git", "init", "-b", "main", str(fake_repo)], check=True, capture_output=True)
            subprocess.run(["git", "-C", str(fake_repo), "config", "user.name", "Test User"], check=True)
            subprocess.run(["git", "-C", str(fake_repo), "config", "user.email", "test@example.com"], check=True)
            # Create an initial commit
            (fake_repo / "README.md").write_text("# Test Repo\n")
            subprocess.run(["git", "-C", str(fake_repo), "add", "README.md"], check=True)
            subprocess.run(["git", "-C", str(fake_repo), "commit", "-m", "Initial commit"], check=True)

            # Copy playbook and scripts into fake_repo
            (fake_repo / "playbooks").mkdir()
            (fake_repo / "scripts").mkdir()
            playbook_copy = fake_repo / "playbooks/sync-ai-sessions.yml"
            playbook_copy.write_text((REPO / "playbooks/sync-ai-sessions.yml").read_text())
            script_copy = fake_repo / "scripts/export_session_index.py"
            script_copy.write_text((REPO / "scripts/export_session_index.py").read_text())
            script_copy.chmod(0o755)

            # Create mock Antigravity CLI structure
            agy_brain = fake_home / ".gemini/antigravity-cli/brain/sess-agy-1"
            agy_brain.mkdir(parents=True)
            (agy_brain / "transcript.jsonl").write_text('{"type": "user", "text": "hello agy"}\n')
            (agy_brain / "session.sock").write_text("socket_content")  # Should be excluded
            (fake_home / ".gemini/antigravity-cli/history.jsonl").write_text("prompt 1\n")

            # Create mock SQLite summaries for agy
            db_path = fake_home / ".gemini/antigravity-cli/conversation_summaries.db"
            conn = sqlite3.connect(str(db_path))
            conn.execute(
                "CREATE TABLE conversation_summaries (conversation_id text, title text, last_modified_time datetime)"
            )
            conn.execute(
                "INSERT INTO conversation_summaries VALUES ('sess-agy-1', 'Mock Agy Conversation', '2026-10-02 12:00:00')"
            )
            conn.commit()
            conn.close()

            # Create mock Claude Code structure
            claude_proj = fake_home / ".claude/projects/-home-test"
            claude_proj.mkdir(parents=True)
            (claude_proj / "sess-claude-1.jsonl").write_text('{"type": "user", "text": "hello claude"}\n')
            (claude_proj / "secret.key").write_text("secret_key_content")  # Should be excluded
            (fake_home / ".claude/history.jsonl").write_text("claude prompt 1\n")

            # Create mock Codex CLI structure
            codex_sess = fake_home / ".codex/sessions/2026/10/02"
            codex_sess.mkdir(parents=True)
            (codex_sess / "rollout-2026-10-02.jsonl").write_text('{"type": "user", "text": "hello codex"}\n')
            (fake_home / ".codex/session_index.jsonl").write_text(
                json.dumps({"id": "01", "thread_name": "Mock Codex", "updated_at": "2026-10-02T10:00:00Z"}) + "\n"
            )
            (fake_home / ".codex/history.jsonl").write_text("codex prompt 1\n")

            # Run ansible-playbook with git_push=false
            ansible_cfg = fake_repo / "ansible.cfg"
            ansible_cfg.write_text("[defaults]\nretry_files_enabled = False\n")

            cmd = [
                "ansible-playbook",
                "-i", "localhost,",
                str(playbook_copy),
                "-e", f"user_home={fake_home}",
                "-e", f"repo_root={fake_repo}",
                "-e", "git_push=false",
            ]
            res = subprocess.run(
                cmd,
                env={**os.environ, "ANSIBLE_CONFIG": str(ansible_cfg)},
                text=True,
                capture_output=True,
                timeout=90,
            )
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

            # Verify sessions directory structure
            sessions_dir = fake_repo / "sessions"
            self.assertTrue(sessions_dir.exists())
            self.assertTrue((sessions_dir / ".gitignore").exists())
            self.assertTrue((sessions_dir / "README.md").exists())
            self.assertTrue((fake_repo / "ai-sessions").is_symlink())

            # Verify agy sync & exclusions
            agy_dest = sessions_dir / "agy"
            self.assertTrue((agy_dest / "sess-agy-1/transcript.jsonl").exists())
            self.assertFalse((agy_dest / "sess-agy-1/session.sock").exists())
            self.assertTrue((agy_dest / "history.jsonl").exists())
            self.assertTrue((agy_dest / "session_index.jsonl").exists())
            index_content = (agy_dest / "session_index.jsonl").read_text()
            self.assertIn("Mock Agy Conversation", index_content)

            # Verify claude sync & exclusions
            claude_dest = sessions_dir / "claude"
            self.assertTrue((claude_dest / "-home-test/sess-claude-1.jsonl").exists())
            self.assertFalse((claude_dest / "-home-test/secret.key").exists())
            self.assertTrue((claude_dest / "history.jsonl").exists())

            # Verify codex sync
            codex_dest = sessions_dir / "codex"
            self.assertTrue((codex_dest / "2026/10/02/rollout-2026-10-02.jsonl").exists())
            self.assertTrue((codex_dest / "session_index.jsonl").exists())
            self.assertTrue((codex_dest / "history.jsonl").exists())

            # Verify git committed the sessions
            log_res = subprocess.run(
                ["git", "-C", str(fake_repo), "log", "--oneline", "-n", "1"],
                text=True, capture_output=True, check=True
            )
            self.assertIn("chore(sessions): sync AI CLI sessions", log_res.stdout)


if __name__ == "__main__":
    unittest.main()
