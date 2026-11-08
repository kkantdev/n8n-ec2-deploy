# Project Memory & Bug Fix Log

## Issue: Library Path Resolution Bug (`lib/lib/docker.sh: No such file or directory`)

- **Reported Error:**
  ```text
  /home/ubuntu/n8n-ec2-deploy/lib/lib/docker.sh: No such file or directory
  ```
- **Expected Library Path:**
  ```text
  /home/ubuntu/n8n-ec2-deploy/lib/docker.sh
  ```
- **Status:** Resolved & Verified

---

### 1. Root Cause Analysis

In `install.sh`, the script directory was originally resolved as:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
When `install.sh` sourced library files sequentially:
```bash
source "${SCRIPT_DIR}/config/defaults.sh"
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/system-checks.sh"
source "${SCRIPT_DIR}/lib/docker.sh"
```
Inside `lib/system-checks.sh` (and several other sub-libraries), the following statement was present at the global script level:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
Because variables in Bash default to global scope, sourcing `lib/system-checks.sh` reassigned `SCRIPT_DIR` from `/home/ubuntu/n8n-ec2-deploy` to `/home/ubuntu/n8n-ec2-deploy/lib`.

When control returned to `install.sh`, line 23 executed:
```bash
source "${SCRIPT_DIR}/lib/docker.sh"
```
Because `SCRIPT_DIR` now held `/home/ubuntu/n8n-ec2-deploy/lib`, Bash attempted to load:
```text
/home/ubuntu/n8n-ec2-deploy/lib/lib/docker.sh
```
which does not exist, throwing `No such file or directory`.

---

### 2. Implementation of the Fix

1. **Established Single Canonical `PROJECT_ROOT`**:
   - `install.sh`, `manage.sh`, and `uninstall.sh` dynamically resolve `PROJECT_ROOT` using `readlink -f` / `realpath` on `BASH_SOURCE[0]`.
   - Canonical directory variables are established and exported:
     - `PROJECT_ROOT`: Root repository path.
     - `LIB_DIR`: `${PROJECT_ROOT}/lib`.
     - `CONFIG_DIR`: `${PROJECT_ROOT}/config`.
     - `PROVIDERS_DIR`: `${PROJECT_ROOT}/providers`.
     - `TEMPLATES_DIR`: `${PROJECT_ROOT}/templates`.

2. **Eliminated Variable Stomping**:
   - Removed all global `SCRIPT_DIR` reassignments across all files in `lib/` and `providers/`.
   - Library files now use scoped checks (`if [[ -z "${PROJECT_ROOT:-}" ... ]]`) and temporary variables that are immediately `unset`.

3. **Pre-sourcing Existence Validation (`load_lib`)**:
   - Implemented a standardized `load_lib` function that checks `[[ -f "$lib_file" ]]` before attempting to source.
   - If any required file is missing, the script halts immediately with an explicit, actionable error message rather than failing with broken partial state.

4. **Sudo & Non-Standard Working Directory Support**:
   - Resolved scripts work when executed from any working directory (`sudo /path/to/n8n-ec2-deploy/install.sh` or `cd /opt && sudo /path/to/install.sh`).
   - No hardcoded paths like `/home/ubuntu/` exist.

5. **Bootstrap & Installed Context Support**:
   - `install.sh` supports curl-pipe bootstrap execution (cloning into a bootstrap directory if executed standalone via pipe).
   - `manage.sh` and `uninstall.sh` seamlessly resolve paths both when executed inside the cloned git repository and when executed inside the installed production directory `/opt/applications/n8n/` (via `.installer/`).

---

### 3. Verification & Test Results

Run tests via `python tests/run-tests.py`:

```text
test_balanced_braces_and_quotes (test_bash_syntax.TestBashScriptIntegrity.test_balanced_braces_and_quotes) ... ok
test_shebangs (test_bash_syntax.TestBashScriptIntegrity.test_shebangs) ... ok
test_templates_exist (test_bash_syntax.TestBashScriptIntegrity.test_templates_exist) ... ok
test_scenario_a_ec2_postgres_public_ip (test_compose_gen.TestComposeGeneration.test_scenario_a_ec2_postgres_public_ip) ... ok
test_scenario_b_ec2_postgres_domain_nginx (test_compose_gen.TestComposeGeneration.test_scenario_b_ec2_postgres_domain_nginx) ... ok
test_scenario_c_ec2_postgres_domain_traefik (test_compose_gen.TestComposeGeneration.test_scenario_c_ec2_postgres_domain_traefik) ... ok
test_scenario_d_supabase_public_ip (test_compose_gen.TestComposeGeneration.test_scenario_d_supabase_public_ip) ... ok
test_scenario_e_supabase_domain_nginx (test_compose_gen.TestComposeGeneration.test_scenario_e_supabase_domain_nginx) ... ok
test_scenario_f_supabase_domain_traefik (test_compose_gen.TestComposeGeneration.test_scenario_f_supabase_domain_traefik) ... ok
test_canonical_directories_exist (test_library_resolution.TestLibraryResolution.test_canonical_directories_exist) ... ok
test_install_sh_library_chain (test_library_resolution.TestLibraryResolution.test_install_sh_library_chain) ... ok
test_manage_sh_library_chain (test_library_resolution.TestLibraryResolution.test_manage_sh_library_chain) ... ok
test_no_double_lib_in_sources (test_library_resolution.TestLibraryResolution.test_no_double_lib_in_sources) ... ok
test_no_global_script_dir_stomping (test_library_resolution.TestLibraryResolution.test_no_global_script_dir_stomping) ... ok
test_uninstall_sh_library_chain (test_library_resolution.TestLibraryResolution.test_uninstall_sh_library_chain) ... ok
test_domain_validation (test_validation.TestValidationUtils.test_domain_validation) ... ok
test_email_validation (test_validation.TestValidationUtils.test_email_validation) ... ok
test_ipv4_validation (test_validation.TestValidationUtils.test_ipv4_validation) ... ok
test_port_validation (test_validation.TestValidationUtils.test_port_validation) ... ok
test_postgres_uri_parsing (test_validation.TestValidationUtils.test_postgres_uri_parsing) ... ok

----------------------------------------------------------------------
Ran 20 tests in 0.106s

OK
[✓ SUCCESS] All test suites passed successfully!
```

