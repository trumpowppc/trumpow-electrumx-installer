#!/bin/bash

RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'   # fixed (was 0,34m)
NC='\033[0m' # No Color

DB_DIR="/db"
UPDATE_ONLY=0
VERBOSE=0
USE_ROCKSDB=1
ELECTRUMX_GIT_URL="https://github.com/trumpowppc/electrumx-trumpow"
ELECTRUMX_GIT_BRANCH="main"

installer=$(realpath "$0")
cd "$(dirname "$0")"

# Self-update
if which git > /dev/null 2>&1; then
  _version_now=$(git rev-parse HEAD 2>/dev/null || echo "")
  git pull > /dev/null 2>&1
  _version_new=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [ -n "$_version_now" ] && [ -n "$_version_new" ] && [ "$_version_now" != "$_version_new" ]; then
    echo "Updated installer."
    exec "$installer" "$@"
  fi
fi

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      cat >&2 <<HELP
Usage: install.sh [OPTIONS]

Install electrumx.

 -h --help                     Show this help
 -v --verbose                  Enable verbose logging
 -d --dbdir dir                Set database directory (default: /db/)
 --update                      Update previously installed version
 --leveldb                     Use LevelDB instead of RocksDB
 --electrumx-git-url url       Install ElectrumX from this URL instead
 --electrumx-git-branch branch Install specific branch of ElectrumX repository
HELP
      exit 0
      ;;
    -d|--dbdir)
      DB_DIR="$2"
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      ;;
    --update)
      UPDATE_ONLY=1
      ;;
    --leveldb)
      USE_ROCKSDB=0
      ;;
    --electrumx-git-url)
      ELECTRUMX_GIT_URL="$2"
      shift
      ;;
    --electrumx-git-branch)
      ELECTRUMX_GIT_BRANCH="$2"
      shift
      ;;
    *)
      echo "WARNING: Unknown option $key" >&2
      exit 12
      ;;
  esac
  shift
done

# redirect child output
: > /tmp/electrumx-installer-$$.log
exec 3>&1 4>&2 2>/tmp/electrumx-installer-$$.log >&2

if [ "$VERBOSE" -eq 1 ]; then
  tail -f /tmp/electrumx-installer-$$.log >&4 &
fi

function _error {
  if [ -s /tmp/electrumx-installer-$$.log ]; then
    echo -en "\n---- LOG OUTPUT BELOW ----\n" >&4
    tail -n 50 /tmp/electrumx-installer-$$.log >&4
    echo -en "\n---- LOG OUTPUT ABOVE ----\n" >&4
  fi
  printf "\r${RED}ERROR:${NC}   %s\n" "$1" >&4
  if (( ${2:--1} > -1 )); then
    exit "$2"
  fi
}

function _warning { printf "\r${YELLOW}WARNING:${NC} %s\n" "$1" >&3; }
function _info    { printf "\r${BLUE}INFO:${NC}    %s\n" "$1" >&3; }

function _status {
  echo -en "\r$1" >&3
  printf "%-75s" " " >&3
  echo -en "\n" >&3
  _progress
}

_progress_count=0
_progress_total=8
function _progress {
  _progress_count=$(( _progress_count + 1 ))
  _pstr="[=======================================================================]"
  _pd=$(( _progress_count * 73 / _progress_total ))
  printf "\r%3d.%1d%% %.${_pd}s" $(( _progress_count * 100 / _progress_total )) $(( (_progress_count * 1000 / _progress_total) % 10 )) $_pstr >&3
}

if [[ $EUID -ne 0 ]]; then
  _error "This script must be run as root (e.g. sudo -H $0)" 1
fi

# Detect distro (optional, but keep your existing behavior)
if [ -f /etc/os-release ]; then
  . /etc/os-release
elif [ -f /etc/issue ]; then
  NAME=$(head -n1 /etc/issue | awk '{print $1}')
else
  _error "Unable to identify Operating System" 2
fi
NAME=$(echo "$NAME" | tr -cd '[[:alnum:]]._-')

# Source distro-specific helpers if present (we override critical ones later)
if [ -f "./distributions/$NAME.sh" ]; then
  . "./distributions/$NAME.sh"
fi

# ---------- Choose Python >= 3.10 ----------
python=""
for _python in python3.12 python3.11 python3.10 python3; do
  if which "$_python" > /dev/null 2>&1; then
    python="$_python"
    break
  fi
done
[ -z "$python" ] && _error "Python 3.10+ not found. Install python3.10 (and python3.10-venv/dev) and retry." 4

pyver=$($python -V 2>&1 | awk '{print $2}')
pymajor=$(echo "$pyver" | cut -d. -f1)
pyminor=$(echo "$pyver" | cut -d. -f2)
if [ "$pymajor" -lt 3 ] || [ "$pyminor" -lt 10 ]; then
  _error "Found $pyver. Please use Python 3.10+ (install python3.10) and re-run." 4
fi

# ---------- Local implementations to FORCE our Python ----------
# If distro scripts define these, our definitions below (later in file) will override them.

install_script_dependencies() {
  apt-get update -y
  apt-get install -y software-properties-common ca-certificates curl gnupg lsb-release
}

add_user() {
  id -u electrumx >/dev/null 2>&1 || adduser --system --quiet --home /var/lib/electrumx --group electrumx
}

create_db_dir() {
  mkdir -p "$1"
  chown electrumx:electrumx "$1"
}

install_git() {
  apt-get install -y git
}

install_pip() {
  $python -m ensurepip --upgrade || true
  $python -m pip install --upgrade pip wheel "setuptools>=65,<70"
}

install_rocksdb() {
  apt-get install -y build-essential \
    librocksdb-dev libsnappy-dev zlib1g-dev libbz2-dev \
    liblz4-dev libzstd-dev
}

install_python_rocksdb() {
  # Build python-rocksdb against system libs with safe pins
  $python -m pip install --upgrade pip "setuptools>=65,<70" "wheel" "Cython<3"
  export CFLAGS="-O2 -fPIC"
  export CXXFLAGS="-O2 -fPIC -std=c++17"
  $python -m pip install --no-binary=:all: python-rocksdb==0.7.0
}

check_pyrocksdb() {
  $python - <<'PY'
try:
    import rocksdb
    print(getattr(rocksdb, "__version__", "ok"))
    exit(0)
except Exception as e:
    print("ERR:", e)
    exit(1)
PY
}

install_leveldb() {
  apt-get install -y build-essential libleveldb-dev python3-dev || true
  $python -m pip install --upgrade pip wheel "setuptools>=65,<70"
  $python -m pip install plyvel
}

install_electrumx() {
  # install runtime deps
  $python -m pip install --upgrade "aiorpcx>=0.22,<0.24" "uvloop" || true
  # install electrumx from your fork/branch
  if [ -d /tmp/electrumx-src ]; then rm -rf /tmp/electrumx-src; fi
  git clone --depth=1 --branch "$ELECTRUMX_GIT_BRANCH" "$ELECTRUMX_GIT_URL" /tmp/electrumx-src
  (cd /tmp/electrumx-src && $python -m pip install .)
}

install_init() {
  # Generate a simple systemd unit pointing to the chosen Python
  cat >/etc/systemd/system/electrumx.service <<UNIT
[Unit]
Description=ElectrumX Server
After=network-online.target
Wants=network-online.target

[Service]
User=electrumx
Group=electrumx
Environment=PYTHONUNBUFFERED=1
LimitNOFILE=8192
EnvironmentFile=-/etc/electrumx.conf
WorkingDirectory=/var/lib/electrumx
ExecStart=$python -m electrumx
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable electrumx.service
}

generate_cert() {
  # Create a self-signed TLS cert if none exists
  mkdir -p /etc/ssl/private /etc/ssl/certs
  if [ ! -f /etc/ssl/private/electrumx.key ] || [ ! -f /etc/ssl/certs/electrumx.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/ssl/private/electrumx.key \
      -out /etc/ssl/certs/electrumx.crt -days 3650 -subj "/CN=localhost"
    chmod 600 /etc/ssl/private/electrumx.key
  fi
}

package_cleanup() {
  apt-get autoremove -y || true
}

# ---------- Main flow ----------

rocksdb_compile=1

if [ "$UPDATE_ONLY" -eq 0 ]; then
  if which electrumx_server > /dev/null 2>&1; then
    _warning "electrumx appears to be installed already; use --update to reinstall."
  fi

  _status "Installing installer dependencies"
  install_script_dependencies

  _status "Adding new user for electrumx"
  add_user

  _status "Creating database directory in $DB_DIR"
  create_db_dir "$DB_DIR"

  _status "Installing git"
  install_git

  if ! $python -m pip --version > /dev/null 2>&1; then
    _progress_total=$(( _progress_total + 1 ))
    _status "Installing pip"
    install_pip
  else
    $python -m pip install --upgrade pip wheel "setuptools>=65,<70" >/dev/null 2>&1 || true
  fi

  if [ "$USE_ROCKSDB" -eq 1 ]; then
    _progress_total=$(( _progress_total + 3 ))
    _status "Installing RocksDB"
    install_rocksdb
    _status "Installing python_rocksdb"
    install_python_rocksdb
    _status "Checking python_rocksdb installation"
    if ! check_pyrocksdb >/dev/null 2>&1; then
      _error "python-rocksdb installation doesn't work" 6
    fi
  else
    _status "Installing LevelDB (plyvel)"
    install_leveldb
  fi

  _status "Installing electrumx"
  install_electrumx

  _status "Installing init scripts"
  install_init

  _status "Generating TLS certificates"
  generate_cert

  if declare -f package_cleanup > /dev/null; then
    _status "Cleaning up"
    package_cleanup
  fi
  _info "ElectrumX has been installed successfully. Edit /etc/electrumx.conf to configure it."
else
  _info "Updating electrumx"
  i=0
  while $python -m pip show electrumx >/dev/null 2>&1; do
    $python -m pip uninstall -y electrumx || true
    ((i++))
    if [ "$i" -gt 5 ]; then
      break
    fi
  done
  install_electrumx
  _info "Installed $($python -m pip freeze | grep -i electrumx)"
fi
