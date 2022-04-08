FROM alpine:3.15 as build-wine
LABEL maintainer="Y.N"

ARG WINEPREFIX
ARG DUMB_INIT_VERSION
ARG UPX_VERSION
ARG DISPLAY
ARG PLATFORM

ENV WINEARCH=win64 \
  WINEDEBUG=fixme-all,err-wineusb,err-ntoskrnl,err-mscoree \
  PLATFORM=${PLATFORM:-x86_64} \
  WINEPREFIX=${WINEPREFIX:-/wine64} \
  DUMB_INIT_VERSION=${DUMB_INIT_VERSION:-1.2.5} \
  UPX_VERSION=${UPX_VERSION:-3.96}

ENV  W_DRIVE_C=${WINEPREFIX}/drive_c \
  W_WINDIR_UNIX=$W_DRIVE_C/windows \
  W_TMP=$W_WINDIR_UNIX/temp/_

RUN set -euxo pipefail \
  && export W_DRIVE_C="${WINEPREFIX}/drive_c" \
  && export W_WINDIR_UNIX="$W_DRIVE_C/windows" \
  && export W_TMP="$W_WINDIR_UNIX/temp/_" \
  && echo "${PLATFORM}" > /etc/apk/arch \
  && apk add -q --no-cache freetype cabextract wget \
  && export repo_mirror=$(head -1 /etc/apk/repositories | sed -nE 's|(/alpine)/.*$|\1|p') \
  && apk add -q --no-cache -X $repo_mirror/edge/community wine \
  && mkdir -p "$W_TMP" \
# from below line, wine is wine64\
  && ln -s /usr/bin/wine64 /usr/bin/wine \
  && for pkg in $(echo "mono gecko"); do \
      mkdir -p /usr/share/wine/$pkg; \
      version=$(wget -q https://dl.winehq.org/wine/wine-${pkg}/ -O - | sed -nE "s|.*=\"([0-9.]+)/.*|\1|p" | sort -n | tail -n1); \
      wget -nv https://dl.winehq.org/wine/wine-${pkg}/${version}/wine-${pkg}-${version}-x86.tar.xz -O - | \
      tar x -J -f - -C /usr/share/wine/${pkg}; \
      wget -nv https://dl.winehq.org/wine/wine-${pkg}/${version}/wine-${pkg}-${version}-x86_64.tar.xz -O - | \
      tar x -J -f - -C /usr/share/wine/${pkg} || true; \
     done \
  && wget -nv https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/bin/winetricks \
  && chmod +x /usr/bin/winetricks \
  && export W_DRIVE_C="${WINEPREFIX}/drive_c" \
  && export W_WINDIR_UNIX="$W_DRIVE_C/windows" \
  && export W_TMP="$W_WINDIR_UNIX/temp/_" \
# somehow it's needed to be done twice to generate registry files e.g. system.reg, user.reg etc.
  && winetricks -q win10 || true \
  && rm -rf ${WINEPREFIX} \
  && winetricks -q win10 || true \
  && wineboot -r \
  && wget -nv -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_x86_64 \
  && chmod +x /usr/bin/dumb-init \
  && wget -O- -nv https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-win64.zip \
    | unzip -p - upx-*/upx.exe > ${W_WINDIR_UNIX}/upx.exe \
  && apk del cabextract wget \
  && rm -rf /var/cache/apk/*

FROM build-wine as build-python
ARG  PYVERSION
ARG  PYINSTALLER_VERSION

ENV PYVERSION=${PYVERSION:-3.9.2} \
  PYINSTALLER_VERSION=${PYINSTALLER_VERSION:-4.5}

RUN set -euxo pipefail \
  && pymajor=${PYVERSION%%.*} pyminor=${PYVERSION#"${pymajor}."} pyminor=${pyminor%.*} \
  && MAJMIN=${pymajor}${pyminor} MAJDOTMIN="${pymajor}.${pyminor}" \
  && if [ $pyminor -ge 10 ]; then \
      export PYINSTALLER_VERSION=4.9; \
    fi \
  && for msifile in $(echo "core dev exe lib path tcltk tools"); do \
      wget -nv "https://www.python.org/ftp/python/${PYVERSION}/amd64/${msifile}.msi"; \
      wine msiexec /i "${msifile}.msi" /qn TARGETDIR=C:/Python${MAJMIN} ALLUSERS=1; \
      wineserver -w; \
      rm -f ${msifile}.msi; \
      done \
  && echo "wine 'C:\Python${MAJMIN}\python.exe' \"\$@\"" > /usr/local/bin/python \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\easy_install-${MAJDOTMIN}.exe' \"\$@\"" > /usr/local/bin/easy_install \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\pip${MAJDOTMIN}.exe' \"\$@\"" > /usr/local/bin/pip \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\pyinstaller.exe' \"\$@\"" > /usr/local/bin/pyinstaller \
  && echo 'assoc .py=PythonScript' | wine cmd \
  && echo "ftype PythonScript=c:\Python${MAJMIN}\python.exe"' "%1" %*' | wine64 cmd \
  && wineserver -w \
  && chmod +x /usr/local/bin/* \
  && python -m ensurepip --upgrade \
  && pip --no-cache-dir install -U pip || true || printf '\033[0m' \
  && pip --no-cache-dir install -U certifi wheel setuptools auditwheel || true \
  && pip --no-cache-dir install -U pyinstaller==${PYINSTALLER_VERSION} \
  && rm -f "$W_TMP"/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["dumb-init","--","/entrypoint.sh"]
