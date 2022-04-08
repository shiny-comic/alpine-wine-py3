#!/bin/sh

set -e
pymajor=${PYVERSION%%.*} pyminor=${PYVERSION#"${pymajor}."} pyminor=${pyminor%.*}

cp "/wine64/drive_c/Python${pymajor}${pyminor}/vcruntime140.dll" /src
WORKDIR=${SRCDIR:-/src}

cd "$WORKDIR"

PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}

echo "PYTHON_VERSION = ${PYVERSION}"
echo "PYINSTALLER_VERSION = ${PYINSTALLER_VERSION}"

if [ -f requirements.txt ]; then
  pip --cache-dir "${PIP_CACHE_DIR:=./pip-cache}" install -r requirements.txt
fi

echo "$@"

for str in "$@"; do
  case $str in
    *.py)
        pyinstaller \
          --clean --noconfirm \
          --onefile \
          --distpath . \
          --workpath /tmp \
          --runtime-tmpdir . \
          -p . \
          $@ ;;
    *.spec)
      exename="${str%.spec}.exe"
      pyinstaller \
        --clean --noconfirm \
          --distpath . \
          --workpath /tmp \
          $str ;;
  esac
done

[ $RUN_EXE ] && wine "$exename" || true
rm -r __pycache__
