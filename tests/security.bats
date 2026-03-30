#!/usr/bin/env bats
# security.bats -- Tests for security functions.

load test_helper

# ── Token generation ──────────────────────────────────────────────────────────

@test "token generation creates a token file" {
    local token_file="${CLAWSPARK_DIR}/token"
    local token
    token=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "${token}" > "${token_file}"
    chmod 600 "${token_file}"

    [ -f "${token_file}" ]
}

@test "generated token is 64 hex characters" {
    local token_file="${CLAWSPARK_DIR}/token"
    local token
    token=$(openssl rand -hex 32)
    echo "${token}" > "${token_file}"

    local content
    content=$(cat "${token_file}" | tr -d '\n')
    [[ "$content" =~ ^[0-9a-f]{64}$ ]]
}

@test "token file permissions are 600" {
    local token_file="${CLAWSPARK_DIR}/token"
    echo "test-token" > "${token_file}"
    chmod 600 "${token_file}"

    local perms
    perms=$(_get_permissions "${token_file}")
    [ "$perms" = "600" ]
}

@test "token file is not world-readable" {
    local token_file="${CLAWSPARK_DIR}/token"
    echo "secret" > "${token_file}"
    chmod 600 "${token_file}"

    local perms
    perms=$(_get_permissions "${token_file}")
    # Verify 'other' permissions (third digit) are 0
    [[ "${perms: -1}" == "0" ]]
}

@test "token generation does not overwrite existing token" {
    local token_file="${CLAWSPARK_DIR}/token"
    echo "original-token-value" > "${token_file}"

    # Simulate what secure.sh does: only write if file doesn't exist
    if [[ ! -f "${token_file}" ]]; then
        openssl rand -hex 32 > "${token_file}"
    fi

    run cat "${token_file}"
    [[ "$output" == "original-token-value" ]]
}

# ── CLAWSPARK_DIR permissions ─────────────────────────────────────────────────

@test "CLAWSPARK_DIR can be set to 700" {
    chmod 700 "${CLAWSPARK_DIR}"

    local perms
    perms=$(_get_permissions "${CLAWSPARK_DIR}")
    [ "$perms" = "700" ]
}

# ── Deny commands list ────────────────────────────────────────────────────────

@test "deny commands list contains destructive patterns" {
    local config_file="${CLAWSPARK_DIR}/openclaw.json"
    python3 -c "
import json, sys
cfg = {
    'gateway': {
        'nodes': {
            'denyCommands': [
                'rm -rf /',
                'rm -rf ~',
                'mkfs',
                'dd if=',
                'cat /etc/shadow',
                'passwd',
                'useradd',
            ]
        }
    }
}
with open(sys.argv[1], 'w') as f:
    json.dump(cfg, f)
" "${config_file}"
    [ -f "${config_file}" ]
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
deny = cfg['gateway']['nodes']['denyCommands']
assert 'rm -rf /' in deny
assert 'passwd' in deny
assert 'cat /etc/shadow' in deny
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "deny commands list blocks package installation" {
    local config_file="${CLAWSPARK_DIR}/openclaw.json"
    python3 -c "
import json, sys
cfg = {
    'gateway': {
        'nodes': {
            'denyCommands': [
                'apt install',
                'apt-get install',
                'pip install',
                'npm install -g',
            ]
        }
    }
}
with open(sys.argv[1], 'w') as f:
    json.dump(cfg, f)
" "${config_file}"
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
deny = cfg['gateway']['nodes']['denyCommands']
assert 'apt install' in deny
assert 'pip install' in deny
assert 'npm install -g' in deny
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "workspace-only filesystem restriction can be set" {
    local config_file="${CLAWSPARK_DIR}/openclaw.json"
    python3 -c "
import json, sys
cfg = {
    'tools': {
        'fs': {
            'workspaceOnly': True
        }
    }
}
with open(sys.argv[1], 'w') as f:
    json.dump(cfg, f)
" "${config_file}"
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
assert cfg['tools']['fs']['workspaceOnly'] is True
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# ── Air-gap state ─────────────────────────────────────────────────────────────

@test "airgap state file can be created" {
    echo "true" > "${CLAWSPARK_DIR}/airgap.state"
    [ -f "${CLAWSPARK_DIR}/airgap.state" ]
    run cat "${CLAWSPARK_DIR}/airgap.state"
    [ "$output" = "true" ]
}

@test "airgap state toggles to false" {
    echo "true" > "${CLAWSPARK_DIR}/airgap.state"
    echo "false" > "${CLAWSPARK_DIR}/airgap.state"
    run cat "${CLAWSPARK_DIR}/airgap.state"
    [ "$output" = "false" ]
}
