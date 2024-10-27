ARG WINEARCH=win64
ARG WINEDEBUG=fixme-all,err-wineusb,err-ntoskrnl,err-mscoree,err-environ
ARG PYVERSION=3.10.11
ARG DUMB_INIT_VERSION=1.2.5

FROM alpine:3.17 as base
ARG DUMB_INIT_VERSION

RUN set -euxo pipefail \
  && apk add -q --no-cache freetype wget xvfb-run cabextract gnutls \
  && for pkg in $(echo "mono gecko"); do \
      mkdir -p /usr/share/wine/$pkg; \
      version=$(wget -q https://dl.winehq.org/wine/wine-${pkg}/ -O - | sed -nE "s|.*=\"([0-9.]+)/.*|\1|p" | sort -n | tail -n1); \
      wget -nv https://dl.winehq.org/wine/wine-${pkg}/${version}/wine-${pkg}-${version}-x86.tar.xz -O - | \
      tar x -J -f - -C /usr/share/wine/${pkg}; \
      ( wget -nv https://dl.winehq.org/wine/wine-${pkg}/${version}/wine-${pkg}-${version}-x86_64.tar.xz -O - | \
        tar x -J -f - -C /usr/share/wine/${pkg} || true ); \
     done \
  && wget -nv https://raw.githubusercontent.com/Winetricks/winetricks/20230212/src/winetricks -O /usr/bin/winetricks \
  && chmod +x /usr/bin/winetricks \
  && wget -nv -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_x86_64 \
  && chmod +x /usr/bin/dumb-init \
  && rm -rf /var/cache/apk/*

FROM base as wine-win64
ARG WINEPREFIX=/win64
ARG WINEARCH
ARG WINEDEBUG

RUN set -euxo pipefail \
  && export W_DRIVE_C="${WINEPREFIX}/drive_c" \
  && export W_WINDIR_UNIX="$W_DRIVE_C/windows" \
  && export repo_mirror=$(head -1 /etc/apk/repositories | sed -nE 's|(/alpine)/.*$|\1|p') \
  && apk add -q --no-cache -X $repo_mirror/edge/community wine \
  && xvfb-run sh -c 'winetricks -q win10 && wineserver -w' \
  && xvfb-run sh -c 'winetricks -q corefonts cjkfonts && wineserver -w' \
  && rm -rf /root/.cache/winetricks \
  && apk del cabextract

FROM wine-win64 as pywine
ARG PYVERSION
ARG CXFREEZE_VERSION=6.14.9
RUN set -euxo pipefail \
  && pymajor=${PYVERSION%%.*} pyminor=${PYVERSION#"${pymajor}."} pyminor=${pyminor%.*} \
  && MAJMIN=${pymajor}${pyminor} MAJDOTMIN="${pymajor}.${pyminor}" \
  && for msi in $(echo "core exe dev lib path tcltk tools"); do \
      wget -nv "https://www.python.org/ftp/python/${PYVERSION}/amd64/${msi}.msi"; \
      xvfb-run -a wine msiexec /i "${msi}.msi" /qn TARGETDIR=C:/Python${MAJMIN} ALLUSERS=1; \
      rm -f ${msi}.msi; \
      done \
  && echo "wine 'C:\Python${MAJMIN}\python.exe' \"\$@\"" > /usr/local/bin/python \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\easy_install-${MAJDOTMIN}.exe' \"\$@\"" > /usr/local/bin/easy_install \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\pip${MAJDOTMIN}.exe' \"\$@\"" > /usr/local/bin/pip \
  && echo "wine 'C:\Python${MAJMIN}\Scripts\cxfreeze.exe' \"\$@\"" > /usr/local/bin/cxfreeze \
  && echo 'assoc .py=PythonScript' | wine cmd \
   && echo "ftype PythonScript=c:\Python${MAJMIN}\python.exe"' "%1" %*' | xvfb-run -a wine cmd \
   && xvfb-run -a wineserver -w \
  && chmod +x /usr/local/bin/* \
  && xvfb-run -a python -V \
  && xvfb-run -a python -m ensurepip \
  && (xvfb-run -a  python -m pip --no-color --no-cache-dir install -U pip || true ) \
  && (xvfb-run -a  pip --no-cache-dir install -U certifi wheel setuptools auditwheel || true ) \
  && xvfb-run -a  pip --no-cache-dir install cx_freeze==${CXFREEZE_VERSION} \
  && apk del xvfb-run \
  && rm -rf /var/cache/apk/*

FROM pywine
ARG WINEARCH
ARG WINEDEBUG
ARG PYVERSION
ARG CXFREEZE_VERSION=6.14.9

ENV PYVERSION=$PYVERSION \
    WINEPREFIX="/"${WINEARCH} \
    CXFREEZE_VERSION=$CXFREEZE_VERSION \
    WINEDEBUG=$WINEDEBUG

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["dumb-init","--","/entrypoint.sh"]
