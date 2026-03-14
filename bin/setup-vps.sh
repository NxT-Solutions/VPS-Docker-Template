#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

SELF_PATH="$SCRIPT_DIR/setup-vps.sh"
CONFIG_FILE="$REPO_ROOT/config/server.env"
RUNTIME_ENV_FILE="$REPO_ROOT/config/runtime/caddy.env"
LOGIN_USER=""
LOGIN_HOME=""
OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""

usage() {
  cat <<EOF
Usage: $SELF_PATH [--config /absolute/or/relative/path/to/server.env]

Bootstraps an Ubuntu 24.04 VPS with Docker, Caddy, Dozzle, and the sample app.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "Missing value for --config."
        CONFIG_FILE="$(resolve_path "$2" "$PWD")"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

ensure_root() {
  if [[ ${EUID} -eq 0 ]]; then
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    die "Run this script as root or with sudo."
  fi

  log "Re-running with sudo."
  exec sudo "$SELF_PATH" --config "$CONFIG_FILE"
}

load_os_release() {
  [[ -f /etc/os-release ]] || die "Cannot detect the operating system."

  # shellcheck disable=SC1091
  source /etc/os-release

  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
  OS_CODENAME="${VERSION_CODENAME:-}"

  [[ "$OS_ID" == "ubuntu" ]] || die "This bootstrap supports Ubuntu only."
  [[ "$OS_VERSION_ID" == "24.04" ]] || die "This bootstrap expects Ubuntu 24.04, found $OS_VERSION_ID."
  [[ -n "$OS_CODENAME" ]] || die "Unable to determine Ubuntu codename."
}

set_login_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    LOGIN_USER="$SUDO_USER"
  else
    LOGIN_USER="$(id -un)"
  fi

  LOGIN_HOME="$(getent passwd "$LOGIN_USER" | cut -d: -f6)"
  [[ -n "$LOGIN_HOME" ]] || die "Unable to determine the home directory for $LOGIN_USER."
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"

  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
}

validate_required_config() {
  local required_vars=(
    ACME_EMAIL
    DOZZLE_DOMAIN
    EXAMPLE_APP_DOMAIN
    BASIC_AUTH_USER
    BASIC_AUTH_PASSWORD
  )
  local missing=()
  local var_name=""

  for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("$var_name")
    fi
  done

  [[ ${#missing[@]} -eq 0 ]] || die "Missing required config values: ${missing[*]}"

  : "${TZ:=UTC}"
  : "${SSH_DISABLE_PASSWORD_AUTH:=true}"
  : "${ENABLE_UFW:=true}"
  : "${ENABLE_FAIL2BAN:=true}"
}

ensure_authorized_key() {
  if ! bool_enabled "$SSH_DISABLE_PASSWORD_AUTH"; then
    return 0
  fi

  local authorized_keys_file="$LOGIN_HOME/.ssh/authorized_keys"

  [[ -f "$authorized_keys_file" ]] || die "Refusing to disable SSH password auth because $authorized_keys_file does not exist."

  if ! grep -Eq '^(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-)' "$authorized_keys_file"; then
    die "Refusing to disable SSH password auth because no public SSH keys were found in $authorized_keys_file."
  fi
}

install_prerequisites() {
  log "Installing prerequisite packages."
  apt-get update -y
  apt-get install -y ca-certificates curl fail2ban gnupg ufw
}

install_docker() {
  log "Installing Docker Engine and the Compose plugin."

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${OS_CODENAME} stable
EOF

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

add_login_user_to_docker_group() {
  if [[ "$LOGIN_USER" == "root" ]]; then
    return 0
  fi

  if id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx docker; then
    log "$LOGIN_USER is already in the docker group."
    return 0
  fi

  usermod -aG docker "$LOGIN_USER"
  warn "$LOGIN_USER was added to the docker group. A new shell session is required before non-sudo Docker commands work for that user."
}

configure_ufw() {
  if ! bool_enabled "$ENABLE_UFW"; then
    warn "Skipping UFW configuration because ENABLE_UFW is disabled."
    return 0
  fi

  log "Configuring UFW."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 443/udp
  ufw --force enable
}

configure_fail2ban() {
  if ! bool_enabled "$ENABLE_FAIL2BAN"; then
    warn "Skipping fail2ban configuration because ENABLE_FAIL2BAN is disabled."
    return 0
  fi

  log "Configuring fail2ban for SSH."
  install -d /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/99-vps-docker-template.local <<'EOF'
[sshd]
enabled = true
backend = systemd
findtime = 10m
maxretry = 5
bantime = 1h
EOF

  systemctl enable --now fail2ban
  systemctl restart fail2ban
}

configure_ssh_password_auth() {
  if ! bool_enabled "$SSH_DISABLE_PASSWORD_AUTH"; then
    warn "Skipping SSH password hardening because SSH_DISABLE_PASSWORD_AUTH is disabled."
    return 0
  fi

  log "Disabling SSH password authentication."
  install -d /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-vps-docker-template.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOF

  sshd -t
  systemctl reload ssh || systemctl reload sshd
}

ensure_runtime_paths() {
  install -d -m 0750 "$REPO_ROOT/config/runtime"
}

generate_basic_auth_hash() {
  log "Generating the shared Caddy basic-auth hash."

  local hash_value
  hash_value="$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "$BASIC_AUTH_PASSWORD" | tr -d '\r')"
  [[ -n "$hash_value" ]] || die "Failed to generate the shared basic-auth hash."

  cat >"$RUNTIME_ENV_FILE" <<EOF
BASIC_AUTH_HASH='$hash_value'
EOF
  chmod 600 "$RUNTIME_ENV_FILE"
}

ensure_docker_network() {
  local network_name="$1"

  if docker network inspect "$network_name" >/dev/null 2>&1; then
    log "Docker network '$network_name' already exists."
    return 0
  fi

  log "Creating Docker network '$network_name'."
  docker network create "$network_name" >/dev/null
}

deploy_stack() {
  local stack_dir="$1"

  log "Deploying stack in $stack_dir."
  run_compose "$stack_dir" up -d
}

assert_running_service() {
  local stack_dir="$1"
  local service_name="$2"

  if ! run_compose "$stack_dir" ps --status running --services | grep -qx "$service_name"; then
    die "Expected service '$service_name' to be running in $stack_dir."
  fi
}

run_compose() {
  local stack_dir="$1"
  shift

  if [[ "$(basename "$stack_dir")" == "caddy" ]]; then
    (
      cd "$stack_dir"
      docker compose --env-file "$CONFIG_FILE" "$@"
    )
    return 0
  fi

  (
    cd "$stack_dir"
    docker compose "$@"
  )
}

check_example_app_route() {
  local https_code
  https_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --resolve "${EXAMPLE_APP_DOMAIN}:443:127.0.0.1" "https://${EXAMPLE_APP_DOMAIN}" || true)"

  if [[ "$https_code" == "200" ]]; then
    log "Verified the example app over HTTPS."
    return 0
  fi

  local http_code
  http_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' -H "Host: ${EXAMPLE_APP_DOMAIN}" http://127.0.0.1/ || true)"

  case "$http_code" in
    301|308)
      warn "The example app is reachable through Caddy, but HTTPS is not ready yet. This usually means DNS or certificate issuance is still in progress."
      ;;
    *)
      die "The example app route did not respond as expected. HTTPS status: ${https_code:-none}, HTTP status: ${http_code:-none}."
      ;;
  esac
}

check_dozzle_route() {
  local https_code
  https_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --user "${BASIC_AUTH_USER}:${BASIC_AUTH_PASSWORD}" --resolve "${DOZZLE_DOMAIN}:443:127.0.0.1" "https://${DOZZLE_DOMAIN}" || true)"

  if [[ "$https_code" == "200" ]]; then
    log "Verified Dozzle over HTTPS."
    return 0
  fi

  local http_code
  http_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' -H "Host: ${DOZZLE_DOMAIN}" http://127.0.0.1/ || true)"

  case "$http_code" in
    301|308)
      warn "Dozzle is reachable through Caddy, but HTTPS is not ready yet. This usually means DNS or certificate issuance is still in progress."
      ;;
    *)
      die "The Dozzle route did not respond as expected. HTTPS status: ${https_code:-none}, HTTP status: ${http_code:-none}."
      ;;
  esac
}

run_smoke_checks() {
  log "Running smoke checks."
  docker info >/dev/null
  docker network inspect web >/dev/null
  docker network inspect internal >/dev/null

  assert_running_service "$REPO_ROOT/example-app" example-app
  assert_running_service "$REPO_ROOT/dozzle" dozzle
  assert_running_service "$REPO_ROOT/caddy" caddy

  check_example_app_route
  check_dozzle_route
}

main() {
  parse_args "$@"
  ensure_root
  load_os_release
  set_login_user
  load_config
  validate_required_config
  ensure_authorized_key
  install_prerequisites
  install_docker
  add_login_user_to_docker_group
  configure_ufw
  configure_fail2ban
  configure_ssh_password_auth
  ensure_runtime_paths
  generate_basic_auth_hash
  ensure_docker_network web
  ensure_docker_network internal
  deploy_stack "$REPO_ROOT/example-app"
  deploy_stack "$REPO_ROOT/dozzle"
  deploy_stack "$REPO_ROOT/caddy"
  run_smoke_checks
  log "Bootstrap complete."
}

main "$@"
