#!/bin/bash

################################################################################
# Frappe Framework Backup Script - Enhanced Error Handling
# Description: Script for automated Frappe sites backups with detailed
#              error diagnostics and recovery options
################################################################################

# ============================================================================
# CONFIGURATION
# ============================================================================

# Bench path (adjust according to your installation)
BENCH_PATH="/home/frappe/frappe-bench"

# Directory where backups will be stored
BACKUP_DIR="/home/frappe/backups"

# Site name (leave empty to backup all sites)
SITE_NAME=""  # Example: "site1.local" or leave empty for all sites

# Backup retention days (older backups will be deleted)
RETENTION_DAYS=7

# Include private and public files in backup
INCLUDE_FILES=true

# Compress backups
COMPRESS_BACKUP=true

# Skip sites with errors and continue with remaining sites
SKIP_ON_ERROR=true

# Verify site health before backup
VERIFY_SITE_HEALTH=true

# Send email notification (requires mail configuration)
SEND_EMAIL=false
EMAIL_TO="admin@example.com"

# Log file
LOG_FILE="$BACKUP_DIR/backup.log"
ERROR_LOG="$BACKUP_DIR/backup_errors.log"

# ============================================================================
# FUNCTIONS
# ============================================================================

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function for error logging
log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
}

# Function to create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log "✓ Backup directory created: $BACKUP_DIR"
    fi
}

# Function to verify site configuration
verify_site_config() {
    local site=$1
    local site_config="$BENCH_PATH/sites/$site/site_config.json"
    
    log "→ Verifying site configuration: $site"
    
    # Check if site_config.json exists
    if [ ! -f "$site_config" ]; then
        log_error "site_config.json not found for site: $site"
        return 1
    fi
    
    # Check if site_config.json is valid JSON
    if ! python3 -c "import json; json.load(open('$site_config'))" 2>/dev/null; then
        log_error "site_config.json is corrupted or invalid JSON for site: $site"
        log "  File location: $site_config"
        log "  Attempting to show content:"
        head -20 "$site_config" | tee -a "$LOG_FILE"
        return 1
    fi
    
    log "✓ site_config.json is valid for: $site"
    return 0
}

# Function to verify database connection
verify_database() {
    local site=$1
    
    log "→ Verifying database connection: $site"
    
    cd "$BENCH_PATH" || return 1
    
    # Try to connect to the database using python
    if echo "import frappe; frappe.init(site='$site'); frappe.connect(); print(frappe.db.get_value('DocType', 'DocType', 'name'))" | bench --site "$site" console 2>/dev/null | grep -q "DocType"; then
        log "✓ Database connection successful for: $site"
        return 0
    else
        log_error "Database connection failed for site: $site"
        
        # Try to get more details about the error
        local db_error=$(echo "import frappe; frappe.init(site='$site'); frappe.connect(); print(frappe.db.get_value('DocType', 'DocType', 'name'))" | bench --site "$site" console 2>&1)
        log "  Database error details:"
        echo "$db_error" | head -10 | tee -a "$LOG_FILE"
        
        return 1
    fi
}

# Function to check site health
check_site_health() {
    local site=$1
    
    log "→ Running health check for site: $site"
    
    # Verify site_config.json
    if ! verify_site_config "$site"; then
        return 1
    fi
    
    # Verify database connection
    if ! verify_database "$site"; then
        return 1
    fi
    
    # Check if site is accessible
    cd "$BENCH_PATH" || return 1
    
    if bench --site "$site" list-apps >/dev/null 2>&1; then
        log "✓ Site is accessible: $site"
    else
        log_error "Site is not accessible: $site"
        return 1
    fi
    
    log "✓ Health check passed for: $site"
    return 0
}

# Function to attempt site recovery
attempt_site_recovery() {
    local site=$1
    
    log "→ Attempting automatic recovery for site: $site"
    
    cd "$BENCH_PATH" || return 1
    
    # Try to migrate the site
    log "  Attempting database migration..."
    if bench --site "$site" migrate 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ Migration completed for: $site"
        return 0
    else
        log_error "Migration failed for: $site"
    fi
    
    # Try to rebuild the site
    log "  Attempting to rebuild..."
    if bench --site "$site" build 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ Rebuild completed for: $site"
        return 0
    else
        log_error "Rebuild failed for: $site"
    fi
    
    return 1
}

# Function to create partial backup (files only)
create_partial_backup() {
    local site=$1
    
    log "→ Creating partial backup (files only) for: $site"
    
    local year=$(date +'%Y')
    local month=$(date +'%m')
    local day=$(date +'%d')
    local timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
    local site_backup_dir="$BACKUP_DIR/$year/$month/$day/$site/$timestamp"
    
    mkdir -p "$site_backup_dir"
    
    # Backup private files
    local private_dir="$BENCH_PATH/sites/$site/private"
    if [ -d "$private_dir" ]; then
        log "  Backing up private files..."
        tar -czf "$site_backup_dir/${site}_private_files_${timestamp}.tar.gz" -C "$BENCH_PATH/sites/$site" private 2>&1 | tee -a "$LOG_FILE"
        log "✓ Private files backed up"
    fi
    
    # Backup public files
    local public_dir="$BENCH_PATH/sites/$site/public"
    if [ -d "$public_dir" ]; then
        log "  Backing up public files..."
        tar -czf "$site_backup_dir/${site}_public_files_${timestamp}.tar.gz" -C "$BENCH_PATH/sites/$site" public 2>&1 | tee -a "$LOG_FILE"
        log "✓ Public files backed up"
    fi
    
    # Backup site_config.json if it exists
    local site_config="$BENCH_PATH/sites/$site/site_config.json"
    if [ -f "$site_config" ]; then
        cp "$site_config" "$site_backup_dir/"
        log "✓ site_config.json backed up"
    fi
    
    # Create warning file
    cat > "$site_backup_dir/WARNING.txt" << EOF
WARNING: PARTIAL BACKUP ONLY
=============================
This is a partial backup created because the database backup failed.

Site: $site
Date: $(date +'%Y-%m-%d %H:%M:%S')
Reason: Database or site_config.json may be corrupted

Contents:
- Private files (if available)
- Public files (if available)
- site_config.json (if available)

DATABASE BACKUP IS MISSING!

Action Required:
1. Check the error log: $ERROR_LOG
2. Investigate database connectivity issues
3. Consider manual database backup using mysqldump
4. Run site health check: bench --site $site console

For manual database backup:
mysqldump -u [user] -p [database_name] > manual_backup.sql
EOF
    
    log "⚠ Partial backup created (no database): $site_backup_dir"
    return 0
}

# Function to perform site backup
backup_site() {
    local site=$1
    log "→ Starting backup for site: $site"
    
    cd "$BENCH_PATH" || {
        log_error "Could not access bench directory: $BENCH_PATH"
        return 1
    }
    
    # Verify site health if enabled
    if [ "$VERIFY_SITE_HEALTH" = true ]; then
        if ! check_site_health "$site"; then
            log "⚠ Health check failed for: $site"
            
            # Attempt recovery
            if attempt_site_recovery "$site"; then
                log "✓ Site recovered, retrying backup: $site"
            else
                log_error "Recovery failed for: $site"
                
                if [ "$SKIP_ON_ERROR" = true ]; then
                    log "⚠ Creating partial backup (files only)"
                    create_partial_backup "$site"
                    return 2  # Partial backup created
                else
                    return 1  # Complete failure
                fi
            fi
        fi
    fi
    
    # Build backup command
    local backup_cmd="bench --site $site backup"
    
    if [ "$INCLUDE_FILES" = true ]; then
        backup_cmd="$backup_cmd --with-files"
    fi
    
    # Execute backup with detailed error capture
    local backup_output
    local backup_exit_code
    
    backup_output=$($backup_cmd 2>&1)
    backup_exit_code=$?
    
    if [ $backup_exit_code -eq 0 ]; then
        log "✓ Backup completed successfully: $site"
        echo "$backup_output" >> "$LOG_FILE"
        
        # Move backups to designated directory
        move_backups "$site"
        
        return 0
    else
        log_error "Backup command failed for: $site"
        log "  Exit code: $backup_exit_code"
        log "  Error output:"
        echo "$backup_output" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
        
        # Check for specific error patterns
        if echo "$backup_output" | grep -q "Access denied"; then
            log_error "Database access denied - check database credentials"
        elif echo "$backup_output" | grep -q "Unknown database"; then
            log_error "Database does not exist"
        elif echo "$backup_output" | grep -q "site_config.json"; then
            log_error "site_config.json is corrupted or missing"
        fi
        
        if [ "$SKIP_ON_ERROR" = true ]; then
            log "⚠ Creating partial backup (files only)"
            create_partial_backup "$site"
            return 2  # Partial backup created
        fi
        
        return 1
    fi
}

# Function to move backups to designated directory
move_backups() {
    local site=$1
    
    local year=$(date +'%Y')
    local month=$(date +'%m')
    local day=$(date +'%d')
    local timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
    
    local site_backup_dir="$BACKUP_DIR/$year/$month/$day/$site/$timestamp"
    
    mkdir -p "$site_backup_dir"
    
    # Move recent backup files
    local source_dir="$BENCH_PATH/sites/$site/private/backups"
    
    if [ -d "$source_dir" ]; then
        # Find files created in the last 2 minutes
        local files_moved=0
        
        while IFS= read -r -d '' file; do
            mv "$file" "$site_backup_dir/"
            ((files_moved++))
        done < <(find "$source_dir" -type f -mmin -2 -print0)
        
        if [ $files_moved -gt 0 ]; then
            log "✓ $files_moved file(s) moved to: $site_backup_dir"
            
            # Compress if enabled
            if [ "$COMPRESS_BACKUP" = true ]; then
                compress_backups "$site_backup_dir"
            fi
            
            # Create metadata file
            create_metadata "$site_backup_dir" "$site" "success"
        else
            log "⚠ No new files found to move"
        fi
    fi
}

# Function to create metadata file
create_metadata() {
    local backup_path=$1
    local site=$2
    local status=$3
    local metadata_file="$backup_path/backup_info.txt"
    
    cat > "$metadata_file" << EOF
Backup Information
==================
Site: $site
Status: $status
Date: $(date +'%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Bench Path: $BENCH_PATH
Files Included: $INCLUDE_FILES
Compressed: $COMPRESS_BACKUP

Files in this backup:
EOF
    
    ls -lh "$backup_path" >> "$metadata_file"
    
    log "✓ Metadata file created"
}

# Function to compress backups
compress_backups() {
    local backup_path=$1
    
    cd "$backup_path" || return
    
    for file in *.sql *.tar; do
        if [ -f "$file" ]; then
            if [[ ! "$file" =~ \.gz$ ]]; then
                gzip "$file"
                log "✓ Compressed: $file"
            fi
        fi
    done
}

# Function to clean up old backups
cleanup_old_backups() {
    log "→ Cleaning up backups older than $RETENTION_DAYS days..."

    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -type d -empty -delete

    log "✓ Cleanup completed"
}

# Function to get list of sites
get_sites() {
    cd "$BENCH_PATH" || exit 1

    if [ -n "$SITE_NAME" ]; then
        echo "$SITE_NAME"
    else
        # List all sites (directories in sites/ that have site_config.json)
        for site_dir in "$BENCH_PATH/sites/"*/; do
            site_name=$(basename "$site_dir")
            # Skip common and localhost
            if [ "$site_name" != "common_site_config.json" ] && [ "$site_name" != "assets" ]; then
                if [ -d "$site_dir" ]; then
                    echo "$site_name"
                fi
            fi
        done
    fi
}

# Function to send email notification
send_notification() {
    local status=$1
    local message=$2

    if [ "$SEND_EMAIL" = true ]; then
        echo "$message" | mail -s "Frappe Backup - $status" "$EMAIL_TO"
    fi
}

# Function to generate summary report
generate_summary_report() {
    local success=$1
    local failed=$2
    local partial=$3
    local total=$4

    local report_file="$BACKUP_DIR/backup_summary_$(date +'%Y-%m-%d').txt"

    cat > "$report_file" << EOF
Frappe Backup Summary Report
============================
Date: $(date +'%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Results:
--------
Total Sites: $total
✓ Successful: $success
✗ Failed: $failed
⚠ Partial: $partial

Success Rate: $(awk "BEGIN {printf \"%.1f\", ($success/$total)*100}")%

Backup Location: $BACKUP_DIR
Log File: $LOG_FILE
Error Log: $ERROR_LOG

Disk Usage:
-----------
EOF
    
    du -sh "$BACKUP_DIR" >> "$report_file"
    df -h "$BACKUP_DIR" | tail -1 >> "$report_file"
    
    if [ $failed -gt 0 ] || [ $partial -gt 0 ]; then
        cat >> "$report_file" << EOF

ATTENTION REQUIRED:
-------------------
Some sites failed to backup completely.
Please review the error log: $ERROR_LOG

Failed/Partial Sites:
EOF
        
        if [ -f "$ERROR_LOG" ]; then
            tail -50 "$ERROR_LOG" >> "$report_file"
        fi
    fi
    
    log "✓ Summary report created: $report_file"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log "════════════════════════════════════════════════════════"
    log "Starting Frappe Framework backup process"
    log "════════════════════════════════════════════════════════"
    
    # Create backup directory
    create_backup_dir
    
    # Counters
    local success_count=0
    local fail_count=0
    local partial_count=0
    local total_sites=0
    
    # Get list of sites
    local sites=$(get_sites)
    
    if [ -z "$sites" ]; then
        log "✗ No sites found to backup"
        exit 1
    fi
    
    # Count sites
    total_sites=$(echo "$sites" | wc -l)
    log "ℹ Sites found: $total_sites"
    
    # Perform backup for each site
    while IFS= read -r site; do
        if [ -n "$site" ]; then
            log ""
            local result
            backup_site "$site"
            result=$?
            
            if [ $result -eq 0 ]; then
                ((success_count++))
            elif [ $result -eq 2 ]; then
                ((partial_count++))
            else
                ((fail_count++))
            fi
        fi
    done <<< "$sites"
    
    # Clean up old backups
    cleanup_old_backups
    
    # Generate summary report
    generate_summary_report "$success_count" "$fail_count" "$partial_count" "$total_sites"
    
    # Final summary
    log ""
    log "════════════════════════════════════════════════════════"
    log "Backup process completed"
    log "✓ Successful: $success_count/$total_sites"
    log "⚠ Partial: $partial_count/$total_sites"
    log "✗ Failed: $fail_count/$total_sites"
    log "════════════════════════════════════════════════════════"
    
    # Send notification
    if [ $fail_count -eq 0 ] && [ $partial_count -eq 0 ]; then
        send_notification "SUCCESS" "Backup completed successfully. Sites backed up: $success_count/$total_sites"
        exit 0
    elif [ $fail_count -eq 0 ]; then
        send_notification "PARTIAL SUCCESS" "Backup completed with partial backups. Successful: $success_count, Partial: $partial_count"
        exit 0
    else
        send_notification "WARNING" "Backup completed with errors. Successful: $success_count, Partial: $partial_count, Failed: $fail_count"
        exit 1
    fi
}

# Execute script
main
