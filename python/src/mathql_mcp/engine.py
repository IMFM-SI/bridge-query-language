"""The MathQL query engine as a persistent subprocess.

The engine speaks JSON Lines over stdin/stdout: one request object per line, one
response object per line (`{"rows": ...}` or `{"error": ...}`; a `{"describe": true}`
request returns the database schema).
"""

import json
import os
import subprocess
import threading
from pathlib import Path
from typing import Any, cast


class Engine:
    """A persistent `mathql` subprocess, addressed one request at a time.

    By default the engine runs `lake exe mathql <name> <db>` from the Lean package
    directory. Setting `MATHQL_BIN` runs that prebuilt binary directly instead.
    """

    def __init__(self, mathql_dir: Path, name: str, db_path: Path) -> None:
        binary = os.environ.get("MATHQL_BIN")
        if binary is not None:
            self.cmd = [binary, name, str(db_path)]
        else:
            self.cmd = ["lake", "exe", "mathql", name, str(db_path)]
        self.cwd = str(mathql_dir)
        self.lock = threading.Lock()
        self.proc: subprocess.Popen[str] | None = None
        self._start()

    def _start(self) -> None:
        self.proc = subprocess.Popen(
            self.cmd, cwd=self.cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )

    def request(self, obj: dict[str, Any]) -> dict[str, Any]:
        """Send one request object and return the decoded response object."""
        with self.lock:
            if self.proc is None or self.proc.poll() is not None:
                self._start()
            assert self.proc is not None and self.proc.stdin is not None
            assert self.proc.stdout is not None
            self.proc.stdin.write(json.dumps(obj) + "\n")
            self.proc.stdin.flush()
            response = self.proc.stdout.readline()
            if not response:
                self._start()
                raise RuntimeError("mathql engine exited without responding")
            return cast(dict[str, Any], json.loads(response))
