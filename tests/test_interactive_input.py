#!/usr/bin/env python3
"""
Test interactive input handling and menu workflows across all wizard options:
1. Database selection (1=EC2 PostgreSQL, 2=Supabase, empty=default 1, 3=validation error then re-prompt)
2. Access method selection (1=public IP, 2=custom domain)
3. Reverse proxy selection (1=Nginx, 2=Traefik, empty=default 1)
4. Ubuntu 26.04 compatibility confirmation (y=continue, n=exit cleanly)
5. prompt_input stderr vs stdout separation
"""

import os
import subprocess
import tempfile
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Locate bash executable
BASH_BIN = None
for candidate in ["C:\\Program Files\\Git\\bin\\bash.exe", "/bin/bash", "/usr/bin/bash", "bash"]:
    try:
        res = subprocess.run([candidate, "--version"], capture_output=True, text=True)
        if res.returncode == 0:
            BASH_BIN = candidate
            break
    except Exception:
        continue


@unittest.skipIf(BASH_BIN is None, "Bash executable not found in environment")
class TestInteractiveInput(unittest.TestCase):
    def run_bash(self, script_code: str, user_input: str = ""):
        """Run a bash snippet and return stdout, stderr, and returncode."""
        env = os.environ.copy()
        env["PROJECT_ROOT"] = PROJECT_ROOT.replace("\\", "/")
        env["LIB_DIR"] = os.path.join(PROJECT_ROOT, "lib").replace("\\", "/")
        env["CONFIG_DIR"] = os.path.join(PROJECT_ROOT, "config").replace("\\", "/")
        env["PROVIDERS_DIR"] = os.path.join(PROJECT_ROOT, "providers").replace("\\", "/")
        env["TEMPLATES_DIR"] = os.path.join(PROJECT_ROOT, "templates").replace("\\", "/")

        proc = subprocess.run(
            [BASH_BIN, "-c", script_code],
            input=user_input,
            capture_output=True,
            text=True,
            env=env,
            timeout=10
        )
        return proc.stdout, proc.stderr, proc.returncode

    def test_prompt_input_stdout_stderr_separation(self):
        """Verify prompt text goes to stderr and entered value goes strictly to stdout."""
        code = f"""
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        choice=$(prompt_input "Enter database choice [1 or 2]" "1")
        echo "CAPTURED:$choice"
        """
        stdout, stderr, code_res = self.run_bash(code, "2\n")
        self.assertEqual(code_res, 0)
        self.assertIn("Enter database choice [1 or 2]", stderr)
        self.assertNotIn("Enter database choice", stdout)
        self.assertEqual(stdout.strip(), "CAPTURED:2")

    def test_prompt_input_default_value(self):
        """Verify empty input returns configured default."""
        code = f"""
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        choice=$(prompt_input "Enter database choice [1 or 2]" "1")
        echo "CAPTURED:$choice"
        """
        stdout, stderr, code_res = self.run_bash(code, "\n")
        self.assertEqual(code_res, 0)
        self.assertEqual(stdout.strip(), "CAPTURED:1")

    def test_database_selection_option_1(self):
        """Database input '1' selects EC2 PostgreSQL."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        source "{PROJECT_ROOT}/lib/database.sh"
        db_ec2_postgres_configure() {{ return 0; }}
        db_supabase_configure() {{ return 0; }}
        prompt_database_selection
        echo "SELECTED:$SELECTED_DB_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "1\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED:ec2-postgres", stdout)

    def test_database_selection_option_2(self):
        """Database input '2' selects Supabase."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        source "{PROJECT_ROOT}/lib/database.sh"
        db_ec2_postgres_configure() {{ return 0; }}
        db_supabase_configure() {{ return 0; }}
        prompt_database_selection
        echo "SELECTED:$SELECTED_DB_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "2\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED:supabase", stdout)

    def test_database_selection_empty_default(self):
        """Empty database input selects default option 1 (EC2 PostgreSQL)."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        source "{PROJECT_ROOT}/lib/database.sh"
        db_ec2_postgres_configure() {{ return 0; }}
        db_supabase_configure() {{ return 0; }}
        prompt_database_selection
        echo "SELECTED:$SELECTED_DB_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED:ec2-postgres", stdout)

    def test_database_selection_invalid_then_valid(self):
        """Database input '3' shows validation error and asks again."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        source "{PROJECT_ROOT}/lib/database.sh"
        db_ec2_postgres_configure() {{ return 0; }}
        db_supabase_configure() {{ return 0; }}
        prompt_database_selection
        echo "SELECTED:$SELECTED_DB_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "3\n1\n")
        self.assertEqual(ret, 0)
        self.assertIn("Invalid selection. Please choose 1 or 2", stderr + stdout)
        self.assertIn("SELECTED:ec2-postgres", stdout)

    def test_access_selection_option_1(self):
        """Access input '1' selects public IP."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        check_port_availability() {{ return 0; }}
        EC2_PUBLIC_IP="1.2.3.4"
        DEFAULT_N8N_PORT="5678"

        eval "$(sed -n '/prompt_access_method_selection()/,/^}}/p' '{PROJECT_ROOT}/install.sh')"
        prompt_proxy_selection() {{ return 0; }}
        prompt_access_method_selection
        echo "SELECTED_ACCESS:$SELECTED_ACCESS_METHOD"
        echo "SELECTED_PROXY:$SELECTED_PROXY_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "1\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED_ACCESS:public-ip", stdout)
        self.assertIn("SELECTED_PROXY:none", stdout)

    def test_access_selection_option_2(self):
        """Access input '2' selects custom domain."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"
        check_port_availability() {{ return 0; }}
        EC2_PUBLIC_IP="1.2.3.4"
        DEFAULT_N8N_PORT="5678"

        eval "$(sed -n '/prompt_access_method_selection()/,/^}}/p' '{PROJECT_ROOT}/install.sh')"
        prompt_proxy_selection() {{ return 0; }}
        prompt_access_method_selection
        echo "SELECTED_ACCESS:$SELECTED_ACCESS_METHOD"
        """
        stdout, stderr, ret = self.run_bash(code, "2\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED_ACCESS:custom-domain", stdout)

    def test_proxy_selection_option_1(self):
        """Proxy input '1' selects Nginx."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"

        eval "$(sed -n '/prompt_proxy_selection()/,/^}}/p' '{PROJECT_ROOT}/install.sh')"
        load_proxy_provider() {{ return 0; }}
        nginx_validate_prerequisites() {{ return 0; }}
        nginx_prompt_config() {{ return 0; }}
        prompt_proxy_selection
        echo "SELECTED_PROXY:$SELECTED_PROXY_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "1\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED_PROXY:nginx", stdout)

    def test_proxy_selection_option_2(self):
        """Proxy input '2' selects Traefik."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"

        eval "$(sed -n '/prompt_proxy_selection()/,/^}}/p' '{PROJECT_ROOT}/install.sh')"
        load_proxy_provider() {{ return 0; }}
        traefik_validate_prerequisites() {{ return 0; }}
        traefik_prompt_config() {{ return 0; }}
        prompt_proxy_selection
        echo "SELECTED_PROXY:$SELECTED_PROXY_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "2\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED_PROXY:traefik", stdout)

    def test_proxy_selection_empty_default(self):
        """Empty proxy input selects default option 1 (Nginx)."""
        code = f"""
        source "{PROJECT_ROOT}/config/defaults.sh"
        source "{PROJECT_ROOT}/lib/colors.sh"
        source "{PROJECT_ROOT}/lib/common.sh"

        eval "$(sed -n '/prompt_proxy_selection()/,/^}}/p' '{PROJECT_ROOT}/install.sh')"
        load_proxy_provider() {{ return 0; }}
        nginx_validate_prerequisites() {{ return 0; }}
        nginx_prompt_config() {{ return 0; }}
        prompt_proxy_selection
        echo "SELECTED_PROXY:$SELECTED_PROXY_PROVIDER"
        """
        stdout, stderr, ret = self.run_bash(code, "\n")
        self.assertEqual(ret, 0)
        self.assertIn("SELECTED_PROXY:nginx", stdout)

    def test_ubuntu_26_04_confirmation_yes(self):
        """Ubuntu 26.04 + confirmation 'y' allows user to continue compatibility verification."""
        with tempfile.NamedTemporaryFile("w", delete=False) as tf:
            tf.write('ID=ubuntu\nVERSION_ID="26.04"\n')
            tf_path = tf.name.replace("\\", "/")

        try:
            code = f"""
            source "{PROJECT_ROOT}/config/defaults.sh"
            source "{PROJECT_ROOT}/lib/colors.sh"
            source "{PROJECT_ROOT}/lib/common.sh"
            source "{PROJECT_ROOT}/lib/validation.sh"

            # Override /etc/os-release path in check_os for testing
            eval "$(sed 's|/etc/os-release|{tf_path}|g' '{PROJECT_ROOT}/lib/system-checks.sh')"

            check_os
            echo "CHECK_OS_EXIT:$?"
            """
            stdout, stderr, ret = self.run_bash(code, "y\n")
            self.assertEqual(ret, 0)
            self.assertIn("CHECK_OS_EXIT:0", stdout)
            self.assertIn("Detected Ubuntu 26.04", stderr + stdout)
            self.assertIn("Continuing installation on Ubuntu 26.04", stderr + stdout)
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_ubuntu_26_04_confirmation_no(self):
        """Ubuntu 26.04 + confirmation 'n' exits cleanly without continuing."""
        with tempfile.NamedTemporaryFile("w", delete=False) as tf:
            tf.write('ID=ubuntu\nVERSION_ID="26.04"\n')
            tf_path = tf.name.replace("\\", "/")

        try:
            code = f"""
            source "{PROJECT_ROOT}/config/defaults.sh"
            source "{PROJECT_ROOT}/lib/colors.sh"
            source "{PROJECT_ROOT}/lib/common.sh"
            source "{PROJECT_ROOT}/lib/validation.sh"

            eval "$(sed 's|/etc/os-release|{tf_path}|g' '{PROJECT_ROOT}/lib/system-checks.sh')"

            check_os
            echo "CHECK_OS_EXIT:$?"
            """
            stdout, stderr, ret = self.run_bash(code, "n\n")
            self.assertIn("CHECK_OS_EXIT:1", stdout)
            self.assertIn("Installation cancelled by user", stderr + stdout)
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

if __name__ == "__main__":
    unittest.main()
