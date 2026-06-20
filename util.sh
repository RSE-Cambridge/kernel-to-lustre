############################################
# Utility functions
############################################
COL_RED="\033[1;31m"
COL_BLUE="\033[1;34m"
COL_PURP="\033[1;35m"
COL_TEAL="\033[1;36m"
COL_ORANGE="\033[0;33m"
COL_YEL="\033[1;33m"
COL_GREEN="\033[1;32m"
COL_WHITE="\033[1;00m"
COL_GREY="\033[1;37m"
COL_CLEAR="\033[0m"

function echo_debug () {
  if [ $DEBUG -gt 0 ]; then
    echo -e "${COL_YEL}[DEBUG] - $@ ${COL_CLEAR}" ;
  fi
}

function echo_info ()  { echo -e "${COL_GREEN}[INFO] - $@ ${COL_CLEAR}" ;}
function echo_warn ()  { echo -e "${COL_PURP}[WARN] - $@ ${COL_CLEAR}" ;}
function echo_error () { echo -e "${COL_RED}[ERROR] - $@ ${COL_CLEAR}" ;}

function die() {
  echo_error "$@" >&2
  exit 1
}

