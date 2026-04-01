#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_vmctl_migration.sh --prom-ip <prometheus-ip> [options]

Required:
  --prom-ip IP           Prometheus IP (example: 10.0.0.12)

Options:
  --snapshot-dir NAME     Skip snapshot API call and use this snapshot directory name
  --namespace NAME        Kubernetes namespace (default: aipub-promstack)
  --pod-name NAME         vmctl pod name (default: vmctl)
  --follow-logs           Follow pod logs after migration command finishes
  -h, --help              Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHART_DIR="$(cd "${INSTALLER_DIR}/.." && pwd)"
VALUES_FILE="${CHART_DIR}/values.yaml"
KI_ENV_PATH="/var/lib/ki-env"
KI_ENV_BIN_PATH="${KI_ENV_PATH}/bin/bin"
YQ_BIN="${KI_ENV_BIN_PATH}/yq"

PROM_IP=""
PROM_URL=""
SNAPSHOT_DIR=""
NAMESPACE="aipub-promstack"
POD_NAME="vmctl"
PVC_NAME="aipub-prometheus-pvc"
VMCTL_IMAGE_REPOSITORY="monitoring/vmctl"
VMCTL_IMAGE_TAG="v1.135.0"
FOLLOW_LOGS="false"

resolve_yq_bin() {
  if [[ -x "${YQ_BIN}" ]]; then
    printf '%s\n' "${YQ_BIN}"
    return 0
  fi
  if command -v yq >/dev/null 2>&1; then
    command -v yq
    return 0
  fi
  echo "yq not found. expected: ${YQ_BIN} or yq in PATH" >&2
  return 1
}

yaml_get_value() {
  local path="$1"
  local yq_cmd="$2"
  "${yq_cmd}" eval -r "explode(.) | ${path}" "${VALUES_FILE}"
}

build_vmctl_image() {
  local yq_cmd="$1"
  local registry=""
  registry="$(yaml_get_value '.imageRegistry // ""' "${yq_cmd}")"
  if [[ -n "${registry}" ]]; then
    printf '%s\n' "${registry%/}/${VMCTL_IMAGE_REPOSITORY}:${VMCTL_IMAGE_TAG}"
  else
    printf '%s\n' "${VMCTL_IMAGE_REPOSITORY}:${VMCTL_IMAGE_TAG}"
  fi
}

apply_vmctl_manifest() {
  local vmctl_image="$1"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
spec:
  containers:
  - command:
    - sh
    - -c
    - sleep 365d
    image: ${vmctl_image}
    imagePullPolicy: IfNotPresent
    name: sh
    volumeMounts:
    - mountPath: /mnt
      name: pv
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      effect: "NoSchedule"
      operator: "Exists"
  volumes:
  - name: pv
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prom-ip)
      PROM_IP="${2:-}"
      PROM_URL="http://${PROM_IP}:9090"
      shift 2
      ;;
    --snapshot-dir)
      SNAPSHOT_DIR="${2:-}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --pod-name)
      POD_NAME="${2:-}"
      shift 2
      ;;
    --follow-logs)
      FOLLOW_LOGS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${PROM_URL}" && -z "${SNAPSHOT_DIR}" ]]; then
  echo "--prom-ip is required unless --snapshot-dir is provided." >&2
  usage >&2
  exit 2
fi

VMCTL_SCRIPT_TEMPLATE="${SCRIPT_DIR}/vmctl_scripts.sh"
USING_METRICS_FILE="${SCRIPT_DIR}/using_metrics.txt"

REMOTE_SCRIPT="/tmp/vmctl_scripts.sh"
REMOTE_ALLOWLIST="/tmp/using_metrics.txt"

for bin in kubectl sed; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Required command not found: $bin" >&2
    exit 1
  fi
done

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "File not found: ${VALUES_FILE}" >&2
  exit 1
fi
if [[ ! -f "${VMCTL_SCRIPT_TEMPLATE}" ]]; then
  echo "File not found: ${VMCTL_SCRIPT_TEMPLATE}" >&2
  exit 1
fi
if [[ ! -f "${USING_METRICS_FILE}" ]]; then
  echo "File not found: ${USING_METRICS_FILE}" >&2
  exit 1
fi

if ! YQ_CMD="$(resolve_yq_bin)"; then
  exit 1
fi
VMCTL_IMAGE="$(build_vmctl_image "${YQ_CMD}")"

echo "[1/4] Apply vmctl pod manifest (image: ${VMCTL_IMAGE})"
apply_vmctl_manifest "${VMCTL_IMAGE}"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${POD_NAME}" --timeout=120s

if [[ -z "${SNAPSHOT_DIR}" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "Required command not found: curl" >&2
    exit 1
  fi

  echo "[2/4] Create Prometheus snapshot"
  SNAPSHOT_RESP="$(
    curl -fsS -X POST "${PROM_URL%/}/api/v1/admin/tsdb/snapshot?skip_head=true"
  )"
  SNAPSHOT_DIR="$(printf '%s' "${SNAPSHOT_RESP}" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"

  if [[ -z "${SNAPSHOT_DIR}" ]]; then
    echo "Failed to parse snapshot_dir from Prometheus response." >&2
    echo "Response: ${SNAPSHOT_RESP}" >&2
    exit 1
  fi
fi

echo "snapshot_dir=${SNAPSHOT_DIR}"

echo "[3/4] Copy script and allowlist to pod"
kubectl -n "${NAMESPACE}" cp "${VMCTL_SCRIPT_TEMPLATE}" "${POD_NAME}:${REMOTE_SCRIPT}"
kubectl -n "${NAMESPACE}" cp "${USING_METRICS_FILE}" "${POD_NAME}:${REMOTE_ALLOWLIST}"
kubectl -n "${NAMESPACE}" exec "${POD_NAME}" -- chmod +x "${REMOTE_SCRIPT}"

echo "[4/4] Run migration"
kubectl -n "${NAMESPACE}" exec -it "${POD_NAME}" -- sh -c \
  "ALLOWLIST_FILE=${REMOTE_ALLOWLIST} VMCTL_BIN=vmctl SNAPSHOT_DIR=${SNAPSHOT_DIR} ${REMOTE_SCRIPT}"

if [[ "${FOLLOW_LOGS}" == "true" ]]; then
  kubectl -n "${NAMESPACE}" logs -f "${POD_NAME}"
fi

echo "Migration command finished."
