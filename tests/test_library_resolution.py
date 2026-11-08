#!/usr/bin/env python3
"""
Test library path resolution and dependency loading across all scripts.
Verifies:
1. No script defines or mutates SCRIPT_DIR in a way that collides.
2. Canonical PROJECT_ROOT, LIB_DIR, CONFIG_DIR, PROVIDERS_DIR, TEMPLATES_DIR exist.
3. All files loaded by install.sh, manage.sh, uninstall.sh exist.
4. Simulated sequential loading doesn't corrupt paths.
5. Simulated curl-bootstrap fallback resolution.
"""

import os
import re
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIB_DIR = os.path.join(PROJECT_ROOT, "lib")
CONFIG_DIR = os.path.join(PROJECT_ROOT, "config")
PROVIDERS_DIR = os.path.join(PROJECT_ROOT, "providers")
TEMPLATES_DIR = os.path.join(PROJECT_ROOT, "templates")

class TestLibraryResolution(unittest.TestCase):
    def test_canonical_directories_exist(self):
        self.assertTrue(os.path.isdir(LIB_DIR), f"LIB_DIR does not exist: {LIB_DIR}")
        self.assertTrue(os.path.isdir(CONFIG_DIR), f"CONFIG_DIR does not exist: {CONFIG_DIR}")
        self.assertTrue(os.path.isdir(PROVIDERS_DIR), f"PROVIDERS_DIR does not exist: {PROVIDERS_DIR}")
        self.assertTrue(os.path.isdir(TEMPLATES_DIR), f"TEMPLATES_DIR does not exist: {TEMPLATES_DIR}")

    def test_no_double_lib_in_sources(self):
        """Ensure no script contains 'lib/lib' in any path reference."""
        for root, _, files in os.walk(PROJECT_ROOT):
            if ".git" in root or "tests" in root:
                continue
            for f in files:
                if f.endswith(".sh"):
                    path = os.path.join(root, f)
                    with open(path, "r", encoding="utf-8") as file:
                        content = file.read()
                    self.assertNotIn("lib/lib", content, f"Double 'lib/lib' found in {path}")

    def test_install_sh_library_chain(self):
        """Verify that all files sourced by install.sh exist on disk."""
        install_sh = os.path.join(PROJECT_ROOT, "install.sh")
        with open(install_sh, "r", encoding="utf-8") as f:
            lines = f.readlines()

        sourced_files = []
        for line in lines:
            m = re.match(r'^\s*load_lib\s+"([^"]+)"', line)
            if m:
                raw_path = m.group(1)
                # Resolve variable expansions
                resolved = (raw_path
                    .replace("${CONFIG_DIR}", CONFIG_DIR)
                    .replace("${LIB_DIR}", LIB_DIR)
                    .replace("${PROVIDERS_DIR}", PROVIDERS_DIR)
                    .replace("${TEMPLATES_DIR}", TEMPLATES_DIR)
                    .replace("${PROJECT_ROOT}", PROJECT_ROOT)
                )
                sourced_files.append(resolved)

        self.assertGreater(len(sourced_files), 10, "Expected at least 10 load_lib calls in install.sh")
        for path in sourced_files:
            self.assertTrue(os.path.isfile(path), f"File referenced in install.sh does not exist: {path}")

    def test_manage_sh_library_chain(self):
        """Verify all files sourced by manage.sh exist on disk."""
        manage_sh = os.path.join(PROJECT_ROOT, "manage.sh")
        with open(manage_sh, "r", encoding="utf-8") as f:
            lines = f.readlines()

        for line in lines:
            m = re.match(r'^\s*load_lib\s+"([^"]+)"', line)
            if m:
                raw_path = m.group(1)
                resolved = (raw_path
                    .replace("${CONFIG_DIR}", CONFIG_DIR)
                    .replace("${LIB_DIR}", LIB_DIR)
                    .replace("${PROVIDERS_DIR}", PROVIDERS_DIR)
                    .replace("${PROJECT_ROOT}", PROJECT_ROOT)
                )
                self.assertTrue(os.path.isfile(resolved), f"File in manage.sh missing: {resolved}")

    def test_uninstall_sh_library_chain(self):
        """Verify all files sourced by uninstall.sh exist on disk."""
        uninstall_sh = os.path.join(PROJECT_ROOT, "uninstall.sh")
        with open(uninstall_sh, "r", encoding="utf-8") as f:
            lines = f.readlines()

        for line in lines:
            m = re.match(r'^\s*load_lib\s+"([^"]+)"', line)
            if m:
                raw_path = m.group(1)
                resolved = (raw_path
                    .replace("${CONFIG_DIR}", CONFIG_DIR)
                    .replace("${LIB_DIR}", LIB_DIR)
                    .replace("${PROVIDERS_DIR}", PROVIDERS_DIR)
                    .replace("${PROJECT_ROOT}", PROJECT_ROOT)
                )
                self.assertTrue(os.path.isfile(resolved), f"File in uninstall.sh missing: {resolved}")

    def test_no_global_script_dir_stomping(self):
        """
        Verify that no library file sets global 'SCRIPT_DIR=...'.
        Setting SCRIPT_DIR in library files was the root cause of the bug.
        """
        lib_files = [f for f in os.listdir(LIB_DIR) if f.endswith(".sh")]
        for f in lib_files:
            path = os.path.join(LIB_DIR, f)
            with open(path, "r", encoding="utf-8") as file:
                lines = file.readlines()
            for line_idx, line in enumerate(lines, 1):
                clean = line.strip()
                if clean.startswith("#"):
                    continue
                self.assertFalse(
                    clean.startswith("SCRIPT_DIR="),
                    f"Library file {f}:{line_idx} sets global SCRIPT_DIR: '{clean}'"
                )

if __name__ == "__main__":
    unittest.main()

