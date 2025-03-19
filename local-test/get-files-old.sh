#!/bin/bash

# Configuración
AUTH_USER="test:tester"
AUTH_KEY="testing"
SWIFT_URL="https://p2mstoragemanager.fly.dev/auth/v1.0"
CONTAINER_NAME="mycontainer"
LOCAL_FILE="localfile.txt"
REMOTE_FILE="file.txt"
DOWNLOADED_FILE="downloaded.txt"
LOG_FILE="swift_script.log"
TEMP_DIR=$(mktemp -d)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuración de seguridad
set -eo pipefail
trap "cleanup" EXIT

# Funciones de utilidad
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %T")
    case $level in
        "INFO") echo -e "${GREEN}[${timestamp} INFO] ${message}${NC}" ;;
        "WARN") echo -e "${YELLOW}[${timestamp} WARN] ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[${timestamp} ERROR] ${message}${NC}" >&2 ;;
    esac
    echo "[${timestamp} ${level}] ${message}" >> "${LOG_FILE}"
}

cleanup() {
    rm -rf "${TEMP_DIR}"
    log "INFO" "Temporary files cleaned up"
}

check_dependencies() {
    local dependencies=("curl" "docker")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            log "ERROR" "Required dependency ${dep} not found"
            exit 1
        fi
    done
}

# Funciones principales
authenticate() {
    log "INFO" "Obtaining authentication token..."
    local response_headers
    response_headers=$(curl -s -i -H "X-Auth-User: ${AUTH_USER}" -H "X-Auth-Key: ${AUTH_KEY}" "${SWIFT_URL}")
    
    TOKEN=$(grep -i "X-Auth-Token" <<< "${response_headers}" | awk '{print $2}' | tr -d '\r')
    STORAGE_URL=$(grep -i "X-Storage-Url" <<< "${response_headers}" | awk '{print $2}' | tr -d '\r')

    if [[ -z "${TOKEN}" || -z "${STORAGE_URL}" ]]; then
        log "ERROR" "Authentication failed"
        check_swift_status
        exit 1
    fi
    
    log "INFO" "Authenticated successfully. Token: ${TOKEN:0:12}****"
}

check_swift_status() {
    log "WARN" "Checking Swift service status..."
    if ! docker exec swift-storage-server swift-init all status >> "${LOG_FILE}" 2>&1; then
        log "ERROR" "Swift services not running properly"
        log "WARN" "Attempting to restart Swift services..."
        docker exec swift-storage-server swift-init all restart >> "${LOG_FILE}" 2>&1
        sleep 5 # Esperar reinicio
    fi
}

create_test_file() {
    log "INFO" "Creating test file..."
    echo "Hello Swift Storage - $(date)" > "${LOCAL_FILE}"
    log "INFO" "Test file created: ${LOCAL_FILE}"
    md5sum "${LOCAL_FILE}" >> "${LOG_FILE}"
}

container_operations() {
    log "INFO" "Listing containers..."
    curl -s -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}" | tee -a "${LOG_FILE}"
    
    log "INFO" "Creating container '${CONTAINER_NAME}'..."
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}/${CONTAINER_NAME}")
    
    if [[ "${status_code}" != 2* ]]; then
        log "ERROR" "Failed to create container (HTTP ${status_code})"
        exit 1
    fi
    log "INFO" "Container created successfully"
}

file_operations() {
    log "INFO" "Uploading file..."
    local upload_status
    upload_status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Auth-Token: ${TOKEN}" -T "${LOCAL_FILE}" "${STORAGE_URL}/${CONTAINER_NAME}/${REMOTE_FILE}")
    
    if [[ "${upload_status}" != 2* ]]; then
        log "ERROR" "Upload failed (HTTP ${upload_status})"
        exit 1
    fi
    log "INFO" "File uploaded successfully"

    log "INFO" "Verifying upload..."
    local file_list
    file_list=$(curl -s -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}/${CONTAINER_NAME}")
    if [[ "${file_list}" != *"${REMOTE_FILE}"* ]]; then
        log "ERROR" "Upload verification failed"
        exit 1
    fi
    log "INFO" "File verified in container"
}

download_and_verify() {
    log "INFO" "Downloading file..."
    curl -s -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}/${CONTAINER_NAME}/${REMOTE_FILE}" -o "${DOWNLOADED_FILE}"
    
    if ! cmp -s "${LOCAL_FILE}" "${DOWNLOADED_FILE}"; then
        log "ERROR" "File verification failed: MD5 mismatch"
        diff -u "${LOCAL_FILE}" "${DOWNLOADED_FILE}" | head -n 20 >> "${LOG_FILE}"
        exit 1
    fi
    log "INFO" "File verification successful"
}

cleanup_operations() {
    log "INFO" "Cleaning up resources..."
    local delete_status
    delete_status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}/${CONTAINER_NAME}/${REMOTE_FILE}")
    
    if [[ "${delete_status}" != 2* ]]; then
        log "WARN" "Failed to delete file (HTTP ${delete_status})"
    else
        log "INFO" "File deleted successfully"
    fi
    
    delete_status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "X-Auth-Token: ${TOKEN}" "${STORAGE_URL}/${CONTAINER_NAME}")
    
    if [[ "${delete_status}" != 2* ]]; then
        log "WARN" "Failed to delete container (HTTP ${delete_status})"
    else
        log "INFO" "Container deleted successfully"
    fi
}

# Ejecución principal
main() {
    check_dependencies
    authenticate
    create_test_file
    container_operations
    file_operations
    download_and_verify
    
    if [[ "$1" == "--cleanup" ]]; then
        cleanup_operations
    else
        log "WARN" "Cleanup skipped. Use --cleanup to remove resources"
    fi
    
    log "INFO" "Script completed successfully"
}

# Ejecutar script principal
main "$@"