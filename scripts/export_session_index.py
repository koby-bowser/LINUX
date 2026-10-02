#!/usr/bin/env python3
"""Export Antigravity CLI conversation summaries SQLite database to session_index.jsonl."""

import json
from pathlib import Path
import sqlite3
import sys


def export_index(db_path: Path, output_path: Path) -> int:
    if not db_path.exists():
        print(f"Database not found: {db_path}", file=sys.stderr)
        return 1

    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        query = (
            "SELECT conversation_id, title, last_modified_time "
            "FROM conversation_summaries "
            "ORDER BY last_modified_time DESC"
        )
        rows = cursor.execute(query).fetchall()
        conn.close()

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as f:
            for row in rows:
                entry = {
                    "id": row[0],
                    "thread_name": row[1],
                    "updated_at": str(row[2]),
                }
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        print(f"Exported {len(rows)} sessions to {output_path}")
        return 0
    except Exception as e:
        print(f"Error exporting session index: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: export_session_index.py <db_path> <output_jsonl_path>", file=sys.stderr)
        sys.exit(2)

    sys.exit(export_index(Path(sys.argv[1]), Path(sys.argv[2])))
