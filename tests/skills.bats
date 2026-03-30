#!/usr/bin/env bats
# skills.bats -- Tests for skill YAML parsing and management.

load test_helper

# Uses _parse_enabled_skills from common.sh (loaded in test_helper.bash)

# ── Parsing tests ─────────────────────────────────────────────────────────────

@test "parse skills extracts 'name:' format entries" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")"
    [[ "$result" == *"test-skill-alpha"* ]]
    [[ "$result" == *"test-skill-beta"* ]]
}

@test "parse skills extracts simple '- slug' format entries" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")"
    [[ "$result" == *"simple-skill"* ]]
    [[ "$result" == *"another-simple"* ]]
}

@test "parse skills returns correct count" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml" | wc -l | tr -d ' ')"
    [ "$result" -eq 4 ]
}

@test "parse skills ignores comments" {
    cat > "${CLAWSPARK_DIR}/skills-commented.yaml" <<'YAML'
skills:
  enabled:
    # - commented-out-skill
    - real-skill
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills-commented.yaml")"
    [[ "$result" != *"commented-out-skill"* ]]
    [[ "$result" == *"real-skill"* ]]
}

@test "parse skills ignores blank lines" {
    cat > "${CLAWSPARK_DIR}/skills-blanks.yaml" <<'YAML'
skills:
  enabled:

    - skill-with-blanks

  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills-blanks.yaml")"
    [[ "$result" == *"skill-with-blanks"* ]]
    count="$(echo "$result" | grep -c 'skill-with-blanks')"
    [ "$count" -eq 1 ]
}

@test "parse skills stops at non-list key" {
    cat > "${CLAWSPARK_DIR}/skills-stop.yaml" <<'YAML'
skills:
  enabled:
    - inside-enabled
  custom:
    - should-not-appear
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills-stop.yaml")"
    [[ "$result" == *"inside-enabled"* ]]
    [[ "$result" != *"should-not-appear"* ]]
}

@test "parse skills handles empty enabled section" {
    cat > "${CLAWSPARK_DIR}/skills-empty.yaml" <<'YAML'
skills:
  enabled:
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills-empty.yaml")"
    [ -z "$result" ]
}

@test "parse skills skips description lines in name format" {
    cat > "${CLAWSPARK_DIR}/skills-desc.yaml" <<'YAML'
skills:
  enabled:
    - name: my-skill
      description: This should not be a skill name
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills-desc.yaml")"
    [[ "$result" == *"my-skill"* ]]
    [[ "$result" != *"This should not"* ]]
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$count" -eq 1 ]
}

# ── _skills_add (inline simulation) ──────────────────────────────────────────

@test "skills_add appends skill to YAML" {
    local skills_file="${CLAWSPARK_DIR}/skills.yaml"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v skill="new-test-skill" '
        /enabled:/ { in_enabled=1 }
        in_enabled && /^[[:space:]]*custom:/ {
            printf "    - name: %s\n      description: User-added skill\n", skill
            in_enabled=0
        }
        { print }
    ' "${skills_file}" > "${tmpfile}"
    mv "${tmpfile}" "${skills_file}"

    run cat "${skills_file}"
    [[ "$output" == *"new-test-skill"* ]]
}

@test "skills_add does not duplicate existing skill" {
    local skills_file="${CLAWSPARK_DIR}/skills.yaml"

    if grep -q "name: test-skill-alpha" "${skills_file}" 2>/dev/null || \
       grep -q "^  *- test-skill-alpha$" "${skills_file}" 2>/dev/null; then
        already_present=true
    else
        already_present=false
    fi

    [ "$already_present" = true ]
}

# ── _skills_remove (inline simulation) ───────────────────────────────────────

@test "skills_remove deletes name-format entry" {
    local skills_file="${CLAWSPARK_DIR}/skills.yaml"
    local name="test-skill-alpha"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v skill="${name}" '
        /^[[:space:]]*- name:/ && $0 ~ skill { skip=1; next }
        skip && /^[[:space:]]+description:/ { skip=0; next }
        skip { skip=0 }
        /^[[:space:]]*-[[:space:]]+/ && $0 ~ skill { next }
        { print }
    ' "${skills_file}" > "${tmpfile}"
    mv "${tmpfile}" "${skills_file}"

    run cat "${skills_file}"
    [[ "$output" != *"test-skill-alpha"* ]]
    [[ "$output" == *"test-skill-beta"* ]]
}

@test "skills_remove deletes simple-format entry" {
    local skills_file="${CLAWSPARK_DIR}/skills.yaml"
    local name="simple-skill"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v skill="${name}" '
        /^[[:space:]]*- name:/ && $0 ~ skill { skip=1; next }
        skip && /^[[:space:]]+description:/ { skip=0; next }
        skip { skip=0 }
        /^[[:space:]]*-[[:space:]]+/ && $0 ~ skill { next }
        { print }
    ' "${skills_file}" > "${tmpfile}"
    mv "${tmpfile}" "${skills_file}"

    run cat "${skills_file}"
    [[ "$output" != *"simple-skill"* ]]
    [[ "$output" == *"another-simple"* ]]
}

# ── Pack listing ──────────────────────────────────────────────────────────────

@test "pack listing parses pack names" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"

    run cat "${packs_file}"
    [[ "$output" == *"testpack"* ]]
    [[ "$output" == *"empty-pack"* ]]
}

@test "pack listing parses descriptions" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"

    run cat "${packs_file}"
    [[ "$output" == *"A test pack"* ]]
    [[ "$output" == *"Empty pack"* ]]
}

@test "pack listing counts skills in testpack" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"
    local in_testpack=false in_skills=false count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*testpack: ]]; then
            in_testpack=true; continue
        fi
        if $in_testpack && [[ "$line" =~ ^[[:space:]]*skills: ]]; then
            in_skills=true; continue
        fi
        if $in_testpack && $in_skills && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            count=$((count + 1)); continue
        fi
        if $in_testpack && [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z] ]] && [[ ! "$line" =~ skills: ]]; then
            break
        fi
    done < "${packs_file}"
    [ "$count" -eq 3 ]
}

@test "parse skills from real project skills.yaml" {
    if [ ! -f "${PROJECT_ROOT}/configs/skills.yaml" ]; then
        skip "Project skills.yaml not found"
    fi
    result="$(_parse_enabled_skills "${PROJECT_ROOT}/configs/skills.yaml")"
    [ -n "$result" ]
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$count" -gt 0 ]
}
