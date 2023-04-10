#!/bin/sh

print () {
  if [ -z "$debug" ]; then
    printf "\033[36m\033[1H$1\033[0m\033[2H"
  else
    printf "$1\n"
  fi
}

set -e
WORKDIR=${SRCDIR:-/src}

cd "$WORKDIR"

PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}

first=$1
while :; do
  case $1 in
    -r|--requirements)
      requirements=$2
      shift; shift
      break
      ;;
    --requierements=*)
      requirements=${1#*=}
      shift
      break
      ;;
    --debug)
      debug="yes"
      set -x
      shift
      first=$1
      ;;
    --random-key)
      if [ "$WINEARCH" = "win64" ]; then
        export USEKEY=1
        random_key=$(pwgen -s 16 1)
      fi
      shift
      first=$1
      ;;
    *)
      tmp=$1
      shift
      set -- $@ $tmp
      [ "$first" = "$1" ] && break
      ;;
  esac
done

clear
[ -z "$debug" ] && printf '\033[2;16r\033[2H'
if [ -f "${requirements:=requirements.txt}" ]; then
  print "pip installation"
  pip --cache-dir "${PIP_CACHE_DIR:=./pip-cache}" install -r ${requirements}
fi

for str in "$@"; do
  case $str in
    *.py)
      print "compiler: pyinstaller, version: ${PYINSTALLER_VERSION}"
        pyinstaller \
          --clean --noconfirm \
          --onefile \
          --distpath ./dist \
          --workpath /tmp \
          -p . \
          ${@/--random-key/--key $random_key}
        break
        ;;
    *.spec)
      print "compiler: pyinstaller, version: ${PYINSTALLER_VERSION} (using spec file)"
      pyinstaller \
        --clean --noconfirm \
          --distpath ./dist \
          --workpath /tmp \
          $@
      break
      ;;
  esac
done
printf '\e[r\e[0m\e[17H'

[ -d "__pycache__" ] && rm -r __pycache__
