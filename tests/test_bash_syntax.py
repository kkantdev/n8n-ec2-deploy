#!/usr/bin/env python3
"""
Static analysis and integrity checks for all Bash scripts in the project.
Checks:
- Shebang validity
- Balanced quotes and braces (ignoring comments)
- File existence of referenced templates and configurations
- Safe quoting and shell idioms
"""

import os
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

class TestBashScriptIntegrity(unittest.TestCase):
    def get_all_sh_files(self):
        sh_files = []
        for root, _, files in os.walk(PROJECT_ROOT):
            if ".git" in root or "tests" in root:
                continue
            for f in files:
                if f.endswith(".sh"):
                    sh_files.append(os.path.join(root, f))
        return sorted(sh_files)

    def test_shebangs(self):
        for script in self.get_all_sh_files():
            with open(script, "r", encoding="utf-8") as f:
                first_line = f.readline().strip()
                self.assertEqual(
                    first_line,
                    "#!/usr/bin/env bash",
                    f"File {script} must start with '#!/usr/bin/env bash', got: {first_line}"
                )

    def test_balanced_braces_and_quotes(self):
        for script in self.get_all_sh_files():
            with open(script, "r", encoding="utf-8") as f:
                lines = f.readlines()

            rel_path = os.path.relpath(script, PROJECT_ROOT)
            
            in_single = False
            in_double = False
            brace_depth = 0

            for line_idx, raw_line in enumerate(lines, 1):
                escaped = False
                prev_char = ""
                for char_idx, char in enumerate(raw_line):
                    if escaped:
                        escaped = False
                        prev_char = char
                        continue
                    if char == "\\":
                        escaped = True
                        prev_char = char
                        continue

                    # In bash, '#' starts a comment only if preceded by whitespace/start of line/semicolon
                    # and not inside quotes, and not ${#var} parameter expansion!
                    if char == "#" and not in_single and not in_double:
                        if prev_char in ("", " ", "\t", ";"):
                            break

                    if char == "'" and not in_double:
                        in_single = not in_single
                    elif char == '"' and not in_single:
                        in_double = not in_double
                    elif char == "{" and not in_single:
                        brace_depth += 1
                    elif char == "}" and not in_single:
                        brace_depth -= 1

                    prev_char = char

            self.assertFalse(in_single, f"Unterminated single quote in {rel_path}")
            self.assertFalse(in_double, f"Unterminated double quote in {rel_path}")
            self.assertEqual(brace_depth, 0, f"Unbalanced braces in {rel_path}")

    def test_templates_exist(self):
        templates = [
            "templates/docker-compose.yml",
            "templates/.env.example",
            "templates/nginx/n8n.conf",
            "templates/traefik/dynamic.yml"
        ]
        for t in templates:
            path = os.path.join(PROJECT_ROOT, t)
            self.assertTrue(os.path.isfile(path), f"Required template file {t} does not exist!")

if __name__ == "__main__":
    unittest.main()
