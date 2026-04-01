#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

print_usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [--cn name] [--days arg] [-o path]
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
--dn            Domain name
--days          Specifies the number of days until a newly generated certificate expires
-o              Output path
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  domain_name=""
  days=365
  output_path="$script_dir_path"/output

  while :; do
    case "${1-}" in
    -h | --help) print_usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    --dn)
      [[ -z "${2-}" ]] && die "Missing required value for option: ${1-}"
      domain_name="${2-}"
      exit_code=0
      echo "$domain_name" | grep -P '(\*\.)?([a-z0-9A-Z]\.)*[a-z0-9-]+\.([a-z0-9]{2,24})+(\.co\.([a-z0-9]{2,24})|\.([a-z0-9]{2,24}))*' > /dev/null 2>&1 || exit_code=$?
      [[ $exit_code != 0 ]] && die 'error: Invalid domain name["'"$domain_name"'"]'
      shift
      ;;
    --days)
      [[ -z "${2-}" ]] && die "Missing required value for option: ${1-}"
      days="${2-}"
      [[ ! $days =~ ^[0-9]+$ ]] && die "error: Value for --days option must be number"
      shift
      ;;
    -o)
      [[ -z "${2-}" ]] && die "Missing required value for option: ${1-}"
      output_path="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  [[ -z "${domain_name-}" ]] && die "Missing required option: --dn"

  return 0
}

parse_params "$@"
setup_colors

templates_path=$script_dir_path/templates

[[ ! -f "$output_path"/ca.crt ]] && die 'error: File["'"$output_path"/ca.crt'"] not exists'
mkdir -p "$output_path"/"$domain_name"
[[ -e "$output_path"/"$domain_name"/tls.crt ]] && die 'error: File["'"$output_path"/"$domain_name"/tls.crt'"] already exists'

cp "$templates_path"/tls.conf "$output_path"/"$domain_name"
cp "$templates_path"/tls.ext "$output_path"/"$domain_name"
sed -i 's/CN =/CN = '"$domain_name"'/g' "$output_path"/"$domain_name"/tls.conf
sed -i 's/DNS.1 =/DNS.1 = '"$domain_name"'/g' "$output_path"/"$domain_name"/tls.ext
openssl req -out "$output_path"/"$domain_name"/tls.csr -keyout "$output_path"/"$domain_name"/tls.key -config "$output_path"/"$domain_name"/tls.conf -newkey rsa
openssl x509 -req -in "$output_path"/"$domain_name"/tls.csr -extfile "$output_path"/"$domain_name"/tls.ext \
  -out "$output_path"/"$domain_name"/tls.crt \
  -CA "$output_path"/ca.crt -CAkey "$output_path"/ca.key -CAcreateserial -days "$days"
