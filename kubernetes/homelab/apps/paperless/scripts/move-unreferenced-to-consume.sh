#!/usr/bin/env bash
#
# move-unreferenced-to-consume.sh
#
# Purpose: Move unreferenced files from Paperless-ngx to the consume directory
#   for re-processing.
#
# Usage:
#   # Dry run (only shows what would be done)
#   DRY_RUN=true ./move-unreferenced-to-consume.sh
#
#   # Execute the moves
#   ./move-unreferenced-to-consume.sh
#
# Rollback Procedure:
#   1. Check the generated manifest file (move-manifest-*.json) for a list of moved files
#   2. To restore files to their original location, use:
#      kubectl --context homelab -n paperless exec paperless-ngx-0 -- mv <dest> <source>
#
# Requirements:
#   - kubectl configured with access to the 'homelab' context
#   - Pod 'paperless-ngx-0' must be running in the 'paperless' namespace
#

set -euo pipefail

# ==============================================================================
# Configuration Section
# ==============================================================================

POD="paperless-ngx-0"
NAMESPACE="paperless"
CONTEXT="homelab"
MANAGE_CMD="/usr/src/paperless/src/manage.py"
CONSUME_DIR="/usr/src/paperless/consume"
BATCH_LIMIT=100

# Allow DRY_RUN to be set via environment variable (default: false)
DRY_RUN="${DRY_RUN:-false}"

# ==============================================================================
# Logging Functions
# ==============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="move-log-${TIMESTAMP}.log"
MANIFEST_FILE="move-manifest-${TIMESTAMP}.json"

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

log_error() {
    log "ERROR: $1" >&2
}

log_warn() {
    log "WARN: $1"
}

log_info() {
    log "INFO: $1"
}

# ==============================================================================
# Pre-Flight Checks
# ==============================================================================

check_kubectl_connectivity() {
    log_info "Verifying kubectl connectivity to context '$CONTEXT'..."

    if ! kubectl --context "$CONTEXT" version >/dev/null 2>&1; then
        log_error "Failed to connect to Kubernetes context '$CONTEXT'"
        exit 1
    fi

    log_info "kubectl connectivity verified"
}

check_pod_running() {
    log_info "Verifying pod '$POD' is running in namespace '$NAMESPACE'..."

    local pod_phase
    pod_phase=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null) || {
        log_error "Failed to get pod status for '$POD'"
        exit 1
    }

    if [[ "$pod_phase" != "Running" ]]; then
        log_error "Pod '$POD' is not running (current phase: $pod_phase)"
        exit 1
    fi

    log_info "Pod '$POD' is running"
}

# ==============================================================================
# Get Unreferenced Files
# ==============================================================================

declare -a UNREFERENCED_FILES=()
declare -A PROCESSED_FILES=()

get_unreferenced_files() {
    log_info "Fetching unreferenced files from Paperless-ngx..."

    local output
    output=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- "$MANAGE_CMD" unreferenced_files 2>/dev/null) || {
        log_error "Failed to execute unreferenced_files command"
        log_error "$output"
        exit 1
    }

    # Parse output into array (one file per line)
    mapfile -t UNREFERENCED_FILES <<< "$output"

    # Filter out empty lines and thumbnail files
    local filtered_files=()
    for file in "${UNREFERENCED_FILES[@]}"; do
        [[ -n "$file" ]] || continue
        [[ "$file" == *"/thumbnails/"* ]] && continue
        filtered_files+=("$file")
    done
    UNREFERENCED_FILES=("${filtered_files[@]}")

    local count=${#UNREFERENCED_FILES[@]}
    log_info "Found $count unreferenced file(s)"

    # Check against batch limit
    if [[ $count -eq 0 ]]; then
        log_info "No unreferenced files to process. Exiting."
        exit 0
    fi

    if [[ $count -gt $BATCH_LIMIT ]]; then
        log_warn "Number of files ($count) exceeds BATCH_LIMIT ($BATCH_LIMIT)"
        log_warn "Only processing first $BATCH_LIMIT files"
        UNREFERENCED_FILES=("${UNREFERENCED_FILES[@]:0:$BATCH_LIMIT}")
    fi
}

# ==============================================================================
# PDF Verification
# ==============================================================================

verify_pdf_mime_type() {
    local file="$1"

    local mime_output
    mime_output=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- file -b --mime-type "$file" 2>/dev/null) || {
        log_warn "Could not determine MIME type for '$file': $mime_output"
        return 1
    }

    if [[ "$mime_output" == "application/pdf" ]]; then
        return 0  # Is PDF
    else
        log_warn "Skipping non-PDF file '$file' (MIME type: $mime_output)"
        return 1  # Not PDF
    fi
}

# ==============================================================================
# JSON Escape Helper
# ==============================================================================

escape_json_string() {
    local input="$1"
    # Escape backslashes first, then quotes
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    echo "$input"
}

# ==============================================================================
# Move Operation
# ==============================================================================

declare -a MOVED_FILES=()
declare -a SKIPPED_FILES=()

move_file_to_consume() {
    local source="$1"
    local filename
    filename=$(basename "$source")
    local destination="$CONSUME_DIR/$filename"

    log_info "Processing: $source"

    # Check if source file still exists
    if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- test -f "$source" 2>/dev/null; then
        log_warn "Source file '$source' no longer exists, skipping"
        SKIPPED_FILES+=("$source")
        return 0
    fi

    # Idempotency check - skip if source was already processed in this run
    if [[ -n "${PROCESSED_FILES[$source]:-}" ]]; then
        log_warn "Source file '$source' already processed in this run, skipping"
        SKIPPED_FILES+=("$source")
        return 0
    fi

    # Verify PDF MIME type
    if ! verify_pdf_mime_type "$source"; then
        SKIPPED_FILES+=("$source")
        return 0
    fi

    # Check if destination exists (collision handling)
    local final_destination="$destination"
    if kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- test -e "$destination" 2>/dev/null; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local name="${filename%.pdf}"
        final_destination="$CONSUME_DIR/${name}_${timestamp}.pdf"
        log_warn "Destination exists, renaming to: $(basename "$final_destination")"
    fi

    # Mark as processed
    PROCESSED_FILES[$source]="1"

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would move: $source -> $final_destination"
        local escaped_source escaped_dest
        escaped_source=$(escape_json_string "$source")
        escaped_dest=$(escape_json_string "$final_destination")
        MOVED_FILES+=("{\"source\": \"$escaped_source\", \"destination\": \"$escaped_dest\", \"status\": \"dry-run\"}")
        return 0
    fi

    # Perform the move
    local move_output
    move_output=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- mv "$source" "$final_destination" 2>&1) || {
        log_error "Failed to move '$source' to '$final_destination': $move_output"
        SKIPPED_FILES+=("$source")
        return 1
    }

    log_info "Successfully moved: $source -> $final_destination"
    local escaped_source escaped_dest
    escaped_source=$(escape_json_string "$source")
    escaped_dest=$(escape_json_string "$final_destination")
    MOVED_FILES+=("{\"source\": \"$escaped_source\", \"destination\": \"$escaped_dest\", \"status\": \"success\"}")

    return 0
}

# ==============================================================================
# Manifest Generation
# ==============================================================================

generate_manifest() {
    log_info "Generating manifest file: $MANIFEST_FILE"

    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"dry_run\": $DRY_RUN,"
        echo "  \"total_processed\": ${#MOVED_FILES[@]},"
        echo "  \"total_skipped\": ${#SKIPPED_FILES[@]},"
        echo "  \"moved\": ["

        for i in "${!MOVED_FILES[@]}"; do
            if [[ $i -lt $((${#MOVED_FILES[@]} - 1)) ]]; then
                echo "    ${MOVED_FILES[$i]},"
            else
                echo "    ${MOVED_FILES[$i]}"
            fi
        done

        echo "  ],"
        echo "  \"skipped\": ["

        for i in "${!SKIPPED_FILES[@]}"; do
            local escaped_skipped
            escaped_skipped=$(escape_json_string "${SKIPPED_FILES[$i]}")
            local skipped_json="\"$escaped_skipped\""
            if [[ $i -lt $((${#SKIPPED_FILES[@]} - 1)) ]]; then
                echo "    $skipped_json,"
            else
                echo "    $skipped_json"
            fi
        done

        echo "  ]"
        echo "}"
    } > "$MANIFEST_FILE"

    log_info "Manifest saved to: $MANIFEST_FILE"
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    log_info "=== Paperless Unreferenced Files Move Script ==="
    log_info "Dry Run: $DRY_RUN"
    log_info "Batch Limit: $BATCH_LIMIT"

    # Pre-flight checks
    check_kubectl_connectivity
    check_pod_running

    # Get unreferenced files
    get_unreferenced_files

    # Process each file
    for file in "${UNREFERENCED_FILES[@]}"; do
        move_file_to_consume "$file"
    done

    # Generate manifest
    generate_manifest

    # Summary
    log_info "=== Summary ==="
    log_info "Total processed: ${#MOVED_FILES[@]}"
    log_info "Total skipped: ${#SKIPPED_FILES[@]}"
    log_info "Log file: $LOG_FILE"
    log_info "Manifest file: $MANIFEST_FILE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No files were actually moved."
        log_info "To execute the moves, run: DRY_RUN=false $0"
    fi

    log_info "Done."
}

main "$@"
