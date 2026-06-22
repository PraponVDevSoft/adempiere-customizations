#!/bin/bash
# =============================================================================
#  Customization Stack Update — TEMPLATE
#
#  Automates the release chain from adempiere-customizations to
#  adempiere-ui-gateway via adempiere-grpc-server.
#
#  NOTE: This is a template. Copy it to scripts/local/stack-update.sh
#  (which is git-ignored) and fill in all values in the CONFIGURE block below.
#
#  NOTE: Template scripts for adempiere-zk and adempiere-processors-service
#  are not yet available. Community contributions are welcome.
#
#  Assumes: commits have already been pushed to your customizations branch.
#
#  Usage:
#    ./scripts/local/stack-update.sh "<release notes>"
#    ./scripts/local/stack-update.sh --dry-run "<release notes>"
#    ./scripts/local/stack-update.sh -n
# =============================================================================

# ── CONFIGURE BEFORE USE ──────────────────────────────────────────────────────
# Fill in all values below for your installation, then save this file to
# scripts/local/stack-update.sh (git-ignored).
#
# This script runs against YOUR OWN FORK of each repository — not against the
# upstream adempiere organization. You must have write access and GitHub Actions
# trigger rights on every repository listed here.
#
CUSTOMIZATIONS_DIR="/path/to/your/adempiere-customizations"
GRPC_DIR="/path/to/your/adempiere-grpc-server"
GW_DIR="/path/to/your/adempiere-ui-gateway"

CUSTOMIZATIONS_REPO="YOUR_ORG/adempiere-customizations"
GRPC_REPO="YOUR_ORG/adempiere-grpc-server"
GW_REPO="YOUR_ORG/adempiere-ui-gateway"

CUSTOMIZATIONS_BRANCH="main"           # branch with your customizations commits
GRPC_BRANCH="master"                   # branch in grpc-server that depends on customizations
GW_BRANCH="main"                       # branch in adempiere-ui-gateway to update

# The groupId under which adempiere-customizations is published (Maven).
# Default for the adempiere org: io.github.adempiere
CUSTOMIZATIONS_GROUP="io.github.adempiere"

# The sed expression that updates the customizations version in the
# grpc-server build.gradle. Adjust the pattern to match your actual
# dependency declaration.
# Example for: implementation 'io.github.adempiere:adempiere-customizations:3.9.4.001-1.0.0'
GRPC_SED_EXPR='s|implementation .'"'"'io\.github\.adempiere:adempiere-customizations:[^'"'"']*'"'"'|implementation '"'"'io.github.adempiere:adempiere-customizations:${CUST_NEW}'"'"'|'
GRPC_SED_VERIFY="adempiere-customizations:"   # string to grep for after sed

# The env_template.env variable and sed expression for grpc-server image in
# adempiere-ui-gateway. Adjust to match your actual variable name and image tag format.
# Example: VUE_BACKEND_GRPC_SERVER_VERSION="1.0.42"
GW_ENV_FILE="docker-compose/env_template.env"
GW_GRPC_VAR="VUE_BACKEND_GRPC_SERVER_VERSION"
# ─────────────────────────────────────────────────────────────────────────────

# ── Configurable polling interval ─────────────────────────────────────────────
POLL_INTERVAL=30    # seconds between CI/CD status checks

# ── Argument parsing ───────────────────────────────────────────────────────────
DRY_RUN=false
RELEASE_NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true ; shift ;;
        *)            RELEASE_NOTES="$1" ; shift ;;
    esac
done

if ! $DRY_RUN && [ -z "$RELEASE_NOTES" ]; then
    SCRIPT=$(basename "$0")
    echo ""
    echo "  Customization Stack Update"
    echo ""
    echo "  Automates the release chain from adempiere-customizations to adempiere-ui-gateway."
    echo "  Assumes: customization commits have already been pushed to ${CUSTOMIZATIONS_BRANCH}."
    echo ""
    echo "  Chain:"
    echo "    adempiere-customizations → adempiere-grpc-server ──► adempiere-ui-gateway"
    echo "    (adempiere-zk and adempiere-processors-service steps not yet implemented)"
    echo ""
    echo "  Usage:"
    echo "    $SCRIPT \"<release notes>\"           real run — commits, pushes, creates releases"
    echo "    $SCRIPT --dry-run \"<release notes>\"  preview only — no changes made"
    echo "    $SCRIPT -n                           dry-run with a default notes placeholder"
    echo ""
    echo "  Options:"
    echo "    --dry-run, -n   Skip all writes. Read-only GitHub calls still run."
    echo "    POLL_INTERVAL   Seconds between CI/CD checks (default: 30s)."
    echo ""
    exit 1
fi
[ -z "$RELEASE_NOTES" ] && RELEASE_NOTES="(dry run — no release will be created)"

# ── Colors & icons ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
OK="✅"; FAIL="❌"

# ── Timing ─────────────────────────────────────────────────────────────────────
SCRIPT_START=$(date +%s)
STEP_START_TS=0

ts()         { date '+%Y-%m-%d %H:%M:%S'; }
ts_epoch()   { date +%s; }

step_start() {
    STEP_START_TS=$(ts_epoch)
    echo ""
    echo -e "${BLUE}${BOLD}─── $* ─────────────────────────────────────────────────${NC}"
    echo    "    Started : $(ts)"
}

step_end() {
    local elapsed=$(( $(ts_epoch) - STEP_START_TS ))
    local mins=$(( elapsed / 60 )) secs=$(( elapsed % 60 ))
    echo    "    Finished: $(ts)"
    printf  "    Duration: %dm %02ds\n" "$mins" "$secs"
    echo -e "    ${GREEN}${OK}  $*${NC}"
}

die() {
    echo -e "${RED}${FAIL}  ERROR [$(ts)]: $*${NC}" >&2
    exit 1
}

# ── Dry-run helpers ────────────────────────────────────────────────────────────
runcmd() {
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi
    "$@"
}

sed_and_verify() {
    local expr="$1" file="$2" pattern="$3" errmsg="$4"
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} sed -i '$expr' $file"
        return 0
    fi
    sed -i "$expr" "$file"
    grep -q "$pattern" "$file" || die "$errmsg"
}

# ── Version helpers ────────────────────────────────────────────────────────────
increment_patch() {
    local v="$1"
    local prefix last
    prefix=$(echo "$v" | sed 's/\.[0-9]*$//')
    last=$(echo "$v"  | grep -oE '[0-9]+$')
    echo "${prefix}.$((last + 1))"
}

latest_release_tag() {
    local repo="$1"
    gh release list --repo "$repo" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null \
        || die "Could not fetch latest release tag from $repo"
}

# ── GitHub Actions helpers ─────────────────────────────────────────────────────
_latest_run_id() {
    local repo="$1" workflow="$2" branch="$3"
    local args=()
    [ -n "$branch" ] && args+=("--branch" "$branch")
    gh run list --repo "$repo" --workflow "$workflow" "${args[@]}" \
        --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "0"
}

snapshot_before() {
    local repo="$1" workflow="$2" branch="${3:-}"
    _latest_run_id "$repo" "$workflow" "$branch"
}

wait_for_workflow() {
    local repo="$1" workflow="$2" before_id="${3:-0}" branch="${4:-}"
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} Would wait for $workflow to complete in $repo"
        return 0
    fi
    local args=()
    [ -n "$branch" ] && args+=("--branch" "$branch")
    local run_id="" attempts=0
    while [ -z "$run_id" ] && [ "$attempts" -lt 12 ]; do
        sleep 15
        local latest
        latest=$(_latest_run_id "$repo" "$workflow" "$branch")
        if [ -n "$latest" ] && [ "$latest" -gt "$before_id" ] 2>/dev/null; then
            run_id="$latest"
        fi
        (( attempts++ )) || true
    done
    [ -z "$run_id" ] && die "No new $workflow run appeared in $repo after $((attempts * 15))s"
    echo "    Run #$run_id — polling every ${POLL_INTERVAL}s"
    while true; do
        local json status conclusion
        json=$(gh run view "$run_id" --repo "$repo" --json status,conclusion 2>/dev/null)
        status=$(echo "$json"     | jq -r '.status')
        conclusion=$(echo "$json" | jq -r '.conclusion')
        if [ "$status" = "completed" ]; then
            [ "$conclusion" = "success" ] && return 0
            die "$workflow run #$run_id in $repo ended with: $conclusion"
        fi
        echo "    $(ts)  $workflow status: $status — next check in ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
    done
}

wait_for_current_workflow() {
    local repo="$1" workflow="$2" branch="$3"
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} Would wait for current $workflow run on $repo/$branch"
        return 0
    fi
    sleep 20
    local run_id
    run_id=$(_latest_run_id "$repo" "$workflow" "$branch")
    [ -z "$run_id" ] || [ "$run_id" = "0" ] && die "No $workflow run found for $repo/$branch"
    echo "    Run #$run_id — polling every ${POLL_INTERVAL}s"
    while true; do
        local json status conclusion
        json=$(gh run view "$run_id" --repo "$repo" --json status,conclusion 2>/dev/null)
        status=$(echo "$json"     | jq -r '.status')
        conclusion=$(echo "$json" | jq -r '.conclusion')
        if [ "$status" = "completed" ]; then
            [ "$conclusion" = "success" ] && return 0
            die "$workflow run #$run_id in $repo ended with: $conclusion"
        fi
        echo "    $(ts)  $workflow status: $status — next check in ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
    done
}

# ── Docker Hub verification ────────────────────────────────────────────────────
verify_docker_image() {
    local image="$1" tag="$2"
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} Would verify Docker image ${image}:${tag} on Docker Hub"
        return 0
    fi
    local url="https://hub.docker.com/v2/repositories/${image}/tags/${tag}/"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null)
    [ "$code" = "200" ] || die "Docker image ${image}:${tag} not found on Docker Hub (HTTP $code)"
    echo -e "    ${GREEN}${OK}  Verified: ${image}:${tag}${NC}"
}

# ── Prerequisites ──────────────────────────────────────────────────────────────
check_prerequisites() {
    local missing=()
    for cmd in gh git jq curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [ ${#missing[@]} -gt 0 ] && die "Missing required tools: ${missing[*]}"
    gh auth status &>/dev/null || die "gh CLI is not authenticated — run: gh auth login"
}

# =============================================================================
# MAIN
# =============================================================================
check_prerequisites

echo ""
echo -e "${BOLD}═════════════════════════════════════════════════════════════${NC}"
if $DRY_RUN; then
echo -e "${BOLD}${YELLOW}  Customization Stack Update  [DRY-RUN — no changes made]${NC}"
else
echo -e "${BOLD}  Customization Stack Update${NC}"
fi
echo    "  Started : $(ts)"
echo    "  Notes   : $RELEASE_NOTES"
echo -e "${BOLD}═════════════════════════════════════════════════════════════${NC}"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — adempiere-customizations: wait for CI, create release, wait for publish
# ─────────────────────────────────────────────────────────────────────────────
step_start "Step 1/3  adempiere-customizations — wait for CI"
cd "$CUSTOMIZATIONS_DIR" || die "Cannot enter $CUSTOMIZATIONS_DIR"
git checkout "$CUSTOMIZATIONS_BRANCH" -q && git pull -q && git fetch --tags -q

CUST_CURRENT=$(latest_release_tag "$CUSTOMIZATIONS_REPO")
COMMITS_AHEAD=$(git rev-list "${CUST_CURRENT}..HEAD" --count 2>/dev/null)
[ -z "$COMMITS_AHEAD" ] && die "Could not count commits ahead of $CUST_CURRENT"
if [ "$COMMITS_AHEAD" -eq 0 ]; then
    echo ""
    echo -e "  ℹ️   adempiere-customizations is up to date — no new commits since tag ${CUST_CURRENT}."
    echo    "      If the change was made in a downstream repository, start the chain from there."
    echo ""
    exit 0
fi
echo "    $COMMITS_AHEAD commit(s) ahead of last release ($CUST_CURRENT)"

wait_for_current_workflow "$CUSTOMIZATIONS_REPO" "ci.yml" "$CUSTOMIZATIONS_BRANCH"
step_end "adempiere-customizations CI passed"

step_start "Step 1/3  adempiere-customizations — create release"
CUST_NEW=$(increment_patch "$CUST_CURRENT")
echo    "    $CUST_CURRENT  →  $CUST_NEW"
BEFORE_CUST_PUBLISH=$(snapshot_before "$CUSTOMIZATIONS_REPO" "publish.yml")
runcmd gh release create "$CUST_NEW" \
    --repo  "$CUSTOMIZATIONS_REPO" \
    --target "$CUSTOMIZATIONS_BRANCH" \
    --title "$CUST_NEW" \
    --notes "$RELEASE_NOTES" \
    || die "Failed to create release $CUST_NEW for adempiere-customizations"
step_end "adempiere-customizations release $CUST_NEW created"

step_start "Step 1/3  adempiere-customizations — wait for publish"
wait_for_workflow "$CUSTOMIZATIONS_REPO" "publish.yml" "$BEFORE_CUST_PUBLISH"
step_end "adempiere-customizations Maven artifact $CUST_NEW published"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — adempiere-grpc-server: update dependency, CI, release, publish, verify
# ─────────────────────────────────────────────────────────────────────────────
step_start "Step 2/3  adempiere-grpc-server — update customizations version"
cd "$GRPC_DIR" || die "Cannot enter $GRPC_DIR"
git checkout "$GRPC_BRANCH" -q && git pull -q && git fetch --tags -q

# Evaluate the sed expression with the new version substituted in
GRPC_SED_EXPR_EVAL=$(eval echo "$GRPC_SED_EXPR")
sed_and_verify \
    "$GRPC_SED_EXPR_EVAL" \
    build.gradle \
    "$GRPC_SED_VERIFY" \
    "sed did not update adempiere-customizations version in adempiere-grpc-server/build.gradle"

BEFORE_GRPC_CI=$(snapshot_before "$GRPC_REPO" "ci.yml" "$GRPC_BRANCH")
runcmd git add build.gradle
runcmd git commit -m "Update adempiere-customizations dependency to ${CUST_NEW}"
runcmd git push origin "$GRPC_BRANCH" || die "Failed to push adempiere-grpc-server"
step_end "adempiere-grpc-server dependency updated and pushed"

step_start "Step 2/3  adempiere-grpc-server — wait for CI"
wait_for_workflow "$GRPC_REPO" "ci.yml" "$BEFORE_GRPC_CI" "$GRPC_BRANCH"
step_end "adempiere-grpc-server CI passed"

step_start "Step 2/3  adempiere-grpc-server — create release"
GRPC_CURRENT=$(latest_release_tag "$GRPC_REPO")
GRPC_NEW=$(increment_patch "$GRPC_CURRENT")
echo    "    $GRPC_CURRENT  →  $GRPC_NEW"
BEFORE_GRPC_PUBLISH=$(snapshot_before "$GRPC_REPO" "publish.yml")
runcmd gh release create "$GRPC_NEW" \
    --repo  "$GRPC_REPO" \
    --target "$GRPC_BRANCH" \
    --title "$GRPC_NEW" \
    --notes "$RELEASE_NOTES" \
    || die "Failed to create release $GRPC_NEW for adempiere-grpc-server"
step_end "adempiere-grpc-server release $GRPC_NEW created"

step_start "Step 2/3  adempiere-grpc-server — wait for publish"
wait_for_workflow "$GRPC_REPO" "publish.yml" "$BEFORE_GRPC_PUBLISH"
$DRY_RUN || { git pull -q && git fetch --tags -q; }
step_end "adempiere-grpc-server publish completed"

step_start "Step 2/3  adempiere-grpc-server — verify Docker image"
# Adjust image name and tag format to match your Docker Hub setup.
# Example: YOUR_DOCKERHUB_ORG/adempiere-grpc-server:${GRPC_NEW}
verify_docker_image "YOUR_DOCKERHUB_ORG/adempiere-grpc-server" "${GRPC_NEW}"
step_end "adempiere-grpc-server Docker image ${GRPC_NEW} verified"


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — adempiere-ui-gateway: update grpc-server image version, commit, push
# ─────────────────────────────────────────────────────────────────────────────
step_start "Step 3/3  adempiere-ui-gateway — update grpc-server image version"
cd "$GW_DIR" || die "Cannot enter $GW_DIR"
git checkout "$GW_BRANCH" -q && git pull -q

sed_and_verify \
    "s|${GW_GRPC_VAR}=\"[^\"]*\"|${GW_GRPC_VAR}=\"${GRPC_NEW}\"|" \
    "$GW_ENV_FILE" \
    "${GW_GRPC_VAR}=\"${GRPC_NEW}\"" \
    "sed did not update ${GW_GRPC_VAR} in $GW_ENV_FILE"

echo "    Updated $GW_ENV_FILE:"
echo "      ${GW_GRPC_VAR} → ${GRPC_NEW}"

runcmd git add "$GW_ENV_FILE"
runcmd git commit -m "Update adempiere-grpc-server image to ${GRPC_NEW}"
runcmd git push origin "$GW_BRANCH" || die "Failed to push adempiere-ui-gateway"
step_end "adempiere-ui-gateway pushed (${GW_BRANCH})"


# =============================================================================
# SUMMARY
# =============================================================================
TOTAL_ELAPSED=$(( $(ts_epoch) - SCRIPT_START ))
TOTAL_MINS=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SECS=$(( TOTAL_ELAPSED % 60 ))

echo ""
echo -e "${BOLD}═════════════════════════════════════════════════════════════${NC}"
if $DRY_RUN; then
echo -e "${BOLD}${YELLOW}  Stack Update Preview Complete  [DRY-RUN — nothing was changed]${NC}"
else
echo -e "${BOLD}  Stack Update Complete${NC}"
fi
echo    "  Finished : $(ts)"
printf  "  Duration : %dm %02ds\n" "$TOTAL_MINS" "$TOTAL_SECS"
echo    "  ─────────────────────────────────────────────────────────"
echo -e "  ${GREEN}${OK}  adempiere-customizations  $CUST_CURRENT  →  $CUST_NEW${NC}"
echo -e "  ${GREEN}${OK}  adempiere-grpc-server     $GRPC_CURRENT  →  $GRPC_NEW${NC}"
echo -e "  ${GREEN}${OK}  adempiere-ui-gateway      $( $DRY_RUN && echo "would push to" || echo "pushed to") ${GW_BRANCH}${NC}"
echo -e "${BOLD}═════════════════════════════════════════════════════════════${NC}"
echo ""
exit 0
