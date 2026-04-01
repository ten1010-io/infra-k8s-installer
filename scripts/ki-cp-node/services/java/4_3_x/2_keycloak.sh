#!/bin/bash

set -e  # Exit on error

#==============================================================================
# 공통 함수 로드
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

JQ_COMMAND="../bin/jq"
YQ_COMMAND="../bin/yq"

# --config 인수 파싱 및 파일 확인
parse_config_arg "$@"
check_config_file

#==============================================================================
# Configuration
#==============================================================================
NAMESPACE=$(${JQ_COMMAND} -r '.namespace' "$CONFIG_FILE")
KEYCLOAK_REALM_NAME=$(${JQ_COMMAND} -r '.keycloak.realm_name' "$CONFIG_FILE")
KEYCLOAK_CLIENT_ID=$(${JQ_COMMAND} -r '.keycloak.client_id' "$CONFIG_FILE")

AIPUB_DOMAIN=$(${JQ_COMMAND} -r '.domain.aipub_domain' "$CONFIG_FILE")
KEYCLOAK_HOST_PREFIX=$(${JQ_COMMAND} -r '.domain.keycloak_host_prefix' "$CONFIG_FILE")
KEYCLOAK_SERVER_URL="https://${KEYCLOAK_HOST_PREFIX}.${AIPUB_DOMAIN}"

KEYCLOAK_REALM_JSON="../templates/keycloak-aipub-realm.json"

export KEYCLOAK_ADMIN_USERNAME="admin"
export KEYCLOAK_ADMIN_PASSWORD=$(get_k8s_secret "keycloak" "${NAMESPACE}" "admin-password")

log_info "=== Keycloak Setup ==="
log_info "URL:            ${KEYCLOAK_SERVER_URL}"
log_info "Admin Username: ${KEYCLOAK_ADMIN_USERNAME}"
log_info "Admin Password: ${KEYCLOAK_ADMIN_PASSWORD:0:5}***"
log_info "Realm:          ${KEYCLOAK_REALM_NAME}"
log_info "Realm JSON:     ${KEYCLOAK_REALM_JSON}"
log_info ""


#==============================================================================
# Keycloak Configuration
#==============================================================================
# 1. Wait for Keycloak
log_info "[1/6] Waiting for Keycloak to be ready..."
until curl -sf "$KEYCLOAK_SERVER_URL/realms/master" > /dev/null 2>&1; do
  log_error "  Not ready yet, retrying in 3s..."
  sleep 3
done
log_info "  Keycloak is up."

# 2. Get admin token
log_info "[2/6] Fetching admin token..."
TOKEN=$(curl -sf \
  -d "client_id=admin-cli" \
  -d "username=${KEYCLOAK_ADMIN_USERNAME}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  "${KEYCLOAK_SERVER_URL}/realms/master/protocol/openid-connect/token" \
  | ${JQ_COMMAND} -r '.access_token')

if [ -z "$TOKEN" ]; then
  log_error "  ERROR: Failed to get admin token." >&2
  exit 1
fi
log_info "  Token acquired."

# 3. Import realm
log_info "[3/6] Importing realm from ${KEYCLOAK_REALM_JSON}..."
HTTP_STATUS=$(curl -s -o kc-import-response.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "@${KEYCLOAK_REALM_JSON}" \
  "${KEYCLOAK_SERVER_URL}/admin/realms")

case $HTTP_STATUS in
  201)
    log_info "  Realm imported successfully."
    ;;
  409)
    log_error "  Realm already exists, skipping import."
    ;;
  *)
    log_error "  ERROR: Import failed with HTTP $HTTP_STATUS" >&2
    cat kc-import-response.json >&2
    exit 1
    ;;
esac

log_info "[4/6] regenerate client secret for '${KEYCLOAK_CLIENT_ID}'..."
CLIENT_UUID=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients?clientId=${KEYCLOAK_CLIENT_ID}" \
  | ${JQ_COMMAND} -r '.[0].id')

NEW_SECRET_RESPONSE=$(curl -s -X POST "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
-H 'Content-Type: application/json' \
-H "Authorization: Bearer $TOKEN")

NEW_SECRET=$(echo $NEW_SECRET_RESPONSE | ${JQ_COMMAND} -r '.value')

log_info "  regenerated Client Secret: $NEW_SECRET"

# 4. Get k8s client secret
log_info "[5/6] Fetching client secret for '${KEYCLOAK_CLIENT_ID}'..."
CLIENT_SECRET=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_SERVER_URL}/admin/realms/${KEYCLOAK_REALM_NAME}/clients/${CLIENT_UUID}/client-secret" \
  | ${JQ_COMMAND} -r '.value')

log_info "  client-secret: $CLIENT_SECRET"

# 5. Get realm public key
log_info "[6/6] Fetching realm public key..."
PUBLIC_KEY=$(curl -sf \
  "${KEYCLOAK_SERVER_URL}/realms/${KEYCLOAK_REALM_NAME}" \
  | ${JQ_COMMAND} -r '.public_key')

log_info "  public-key: $PUBLIC_KEY"


# 6. clean up token
log_info "Revoking admin token..."
curl -sf -X POST \
  -d "token=${TOKEN}" \
  -d "client_id=admin-cli" \
  "${KEYCLOAK_SERVER_URL}/realms/master/protocol/openid-connect/revoke" > /dev/null
log_info "  Token revoked."

# 6-1. Verify token is invalid (expect 401)
log_info "[8/8] Verifying token is revoked..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "${KEYCLOAK_SERVER_URL}/admin/realms")

if [ "$HTTP_STATUS" = "401" ]; then
  log_info "  OK: Token rejected with 401."
else
  log_info "  WARNING: Expected 401 but got $HTTP_STATUS." >&2
fi

log_info ""
log_info "=== Done ==="
