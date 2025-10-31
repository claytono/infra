#!/bin/bash
#
# Bookshelf Custom Script - Copy to CWA Ingest
#
# Triggered on:
# - On Release Import (Readarr_EventType=Download)
# - On Upgrade (Readarr_EventType=Download with deleted files)
# - On Book Retag (Readarr_EventType=TrackRetag)
#
# Environment variables (verified from source code):
# Note: Variables are passed as lowercase by the system
# - readarr_eventtype: Event type (Download, TrackRetag, Test)
# - readarr_addedbookpaths: Pipe-separated list of book file paths (Download event)
# - readarr_bookfile_path: Single book file path (TrackRetag event)
# - readarr_author_name: Author name
# - readarr_book_title: Book title
# - readarr_deletedpaths: Pipe-separated list of deleted files (upgrades only)

set -e

# Configuration
CWA_INGEST_DIR="/cwa-book-ingest"
LOG_FILE="/config/logs/copy-to-cwa.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Copy function
copy_to_cwa() {
    local book_path="$1"

    if [ -z "$book_path" ]; then
        log "WARNING: Empty book path provided, skipping"
        return 1
    fi

    if [ ! -f "$book_path" ]; then
        log "ERROR: Book file does not exist: $book_path"
        return 1
    fi

    local filename=$(basename "$book_path")

    log "Copying: $filename"
    if cp -v "$book_path" "$CWA_INGEST_DIR/$filename" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: Copied to $CWA_INGEST_DIR/$filename"
        return 0
    else
        log "ERROR: Failed to copy $filename"
        return 1
    fi
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log "=========================================="
log "DEBUG: All Readarr environment variables:"
env | grep -i readarr | sort >> "$LOG_FILE" 2>&1 || log "No readarr environment variables found"
log "=========================================="
log "Event Type: ${readarr_eventtype:-Unknown}"
log "Author: ${readarr_author_name:-Unknown}"
log "Book: ${readarr_book_title:-Unknown}"

# Handle different event types
case "$readarr_eventtype" in
    Download)
        log "Processing Download/Import event"

        if [ -n "$readarr_deletedpaths" ]; then
            log "This is an UPGRADE (old files will be replaced)"
            log "Deleted files: $readarr_deletedpaths"
        fi

        if [ -z "$readarr_addedbookpaths" ]; then
            log "ERROR: No book paths provided in readarr_addedbookpaths"
            exit 1
        fi

        log "Added book paths: $readarr_addedbookpaths"

        # Parse pipe-separated paths
        IFS='|' read -ra BOOK_PATHS <<< "$readarr_addedbookpaths"

        success_count=0
        fail_count=0

        for book_path in "${BOOK_PATHS[@]}"; do
            if copy_to_cwa "$book_path"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        done

        log "Summary: $success_count succeeded, $fail_count failed"

        if [ $fail_count -gt 0 ]; then
            exit 1
        fi
        ;;

    TrackRetag)
        log "Processing Book Retag event (metadata update)"
        log "Book file: ${readarr_bookfile_path:-Unknown}"

        if [ -z "$readarr_bookfile_path" ]; then
            log "ERROR: No book file path provided in readarr_bookfile_path"
            exit 1
        fi

        copy_to_cwa "$readarr_bookfile_path"
        ;;

    Test)
        log "Test event received - script is working correctly!"
        log "Script will copy books to: $CWA_INGEST_DIR"
        log "Logs are written to: $LOG_FILE"
        exit 0
        ;;

    *)
        log "ERROR: Unknown event type: $readarr_eventtype"
        log "This script handles: Download, TrackRetag, Test"
        exit 1
        ;;
esac

log "Script completed successfully"
exit 0
