#!/bin/bash
#
# Bookshelf Custom Script - Copy to Book Ingest Directories
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
#
# Command-line flags:
# --cwa: Copy to CWA only
# --booklore: Copy to Booklore only
# --both: Copy to both (default if no flags specified)

set -e

# Parse command-line arguments
COPY_CWA=false
COPY_BOOKLORE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cwa)
            COPY_CWA=true
            shift
            ;;
        --booklore)
            COPY_BOOKLORE=true
            shift
            ;;
        --both)
            COPY_CWA=true
            COPY_BOOKLORE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--cwa] [--booklore] [--both]"
            exit 1
            ;;
    esac
done

# Default to both if no flags specified
if [ "$COPY_CWA" = false ] && [ "$COPY_BOOKLORE" = false ]; then
    COPY_CWA=true
    COPY_BOOKLORE=true
fi

# Configuration
CWA_INGEST_DIR="/cwa-book-ingest"
BOOKLORE_INGEST_DIR="/booklore-book-ingest"
LOG_FILE="/config/logs/copy-to-ingest.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Copy function
copy_book() {
    local book_path="$1"
    local dest_dir="$2"
    local dest_name="$3"

    if [ -z "$book_path" ]; then
        log "WARNING: Empty book path provided, skipping"
        return 1
    fi

    if [ ! -f "$book_path" ]; then
        log "ERROR: Book file does not exist: $book_path"
        return 1
    fi

    local filename=$(basename "$book_path")

    log "Copying to $dest_name: $filename"
    if cp -v "$book_path" "$dest_dir/$filename" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: Copied to $dest_dir/$filename"
        return 0
    else
        log "ERROR: Failed to copy $filename to $dest_name"
        return 1
    fi
}

# Process a book to configured destinations
process_book() {
    local book_path="$1"
    local any_success=false
    local any_failure=false

    if [ "$COPY_CWA" = true ]; then
        if copy_book "$book_path" "$CWA_INGEST_DIR" "CWA"; then
            any_success=true
        else
            any_failure=true
        fi
    fi

    if [ "$COPY_BOOKLORE" = true ]; then
        if copy_book "$book_path" "$BOOKLORE_INGEST_DIR" "Booklore"; then
            any_success=true
        else
            any_failure=true
        fi
    fi

    # Return failure if any copy failed
    if [ "$any_failure" = true ]; then
        return 1
    else
        return 0
    fi
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log "=========================================="
log "Configuration:"
log "  Copy to CWA: $COPY_CWA"
log "  Copy to Booklore: $COPY_BOOKLORE"
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
            if process_book "$book_path"; then
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

        if ! process_book "$readarr_bookfile_path"; then
            log "ERROR: Failed to process book"
            exit 1
        fi
        ;;

    Test)
        log "Test event received - script is working correctly!"
        if [ "$COPY_CWA" = true ]; then
            log "Script will copy books to CWA: $CWA_INGEST_DIR"
        fi
        if [ "$COPY_BOOKLORE" = true ]; then
            log "Script will copy books to Booklore: $BOOKLORE_INGEST_DIR"
        fi
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
