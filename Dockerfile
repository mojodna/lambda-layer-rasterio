FROM lambci/lambda:build-python3.6

ARG http_proxy
#ARG CURL_VERSION=7.63.0
ARG CURL_VERSION=7.51.0
ARG GDAL_VERSION=2.4.0
ARG LIBJPEG_TURBO_VERSION=2.0.1
ARG NGHTTP2_VERSION=1.35.1
ARG PROJ_VERSION=5.2.0
ARG WEBP_VERSION=1.0.1
ARG LIBZSTD_VERSION=1.3.8

# Install deps

RUN \
  rpm --rebuilddb && \
  yum install -y \
    automake16 \
    libpng-devel \
    nasm

# Fetch and build nghttp2

RUN mkdir /tmp/nghttp2 \
  && curl -sfL https://github.com/nghttp2/nghttp2/releases/download/v${NGHTTP2_VERSION}/nghttp2-${NGHTTP2_VERSION}.tar.gz | tar zxf - -C /tmp/nghttp2 --strip-components=1 \
  && cd /tmp/nghttp2 \
  && ./configure --enable-lib-only --prefix=/opt \
  && make -j $(nproc) install

# Fetch and install libcurl

RUN mkdir /tmp/curl \
  && curl -sfL https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz | tar zxf - -C /tmp/curl --strip-components=1 \
  && cd /tmp/curl \
  && ./configure --prefix=/opt --disable-manual --disable-cookies --with-nghttp2=/opt \
  && make -j $(nproc) install

# Fetch PROJ.4

RUN \
  curl -sfL http://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz | tar zxf - -C /tmp

# Build and install PROJ.4

WORKDIR /tmp/proj-${PROJ_VERSION}

RUN \
  ./configure \
    --prefix=/opt && \
  make -j $(nproc) && \
  make install

# Build and install libjpeg-turbo

RUN mkdir -p /tmp/libjpeg-turbo \
  && curl -sfL https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${LIBJPEG_TURBO_VERSION}.tar.gz | tar zxf - -C /tmp/libjpeg-turbo --strip-components=1 \
  && cd /tmp/libjpeg-turbo \
  && cmake -G"Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/opt . \
  && make -j $(nproc) install

## webp

RUN mkdir -p /tmp/webp \
    && cd /tmp/webp \
    && curl -f -L -O https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz \
    && tar xzf libwebp-${WEBP_VERSION}.tar.gz \
    && cd libwebp-${WEBP_VERSION} \
    && CFLAGS="-O2" ./configure --prefix=/opt \
    && make \
    && make install

## libszstd

RUN mkdir -p /tmp/libszstd \
    && cd /tmp/libszstd \
    && curl -f -L -O https://github.com/facebook/zstd/archive/v${LIBZSTD_VERSION}.zip \
    && unzip v${LIBZSTD_VERSION}.zip \
    && cd zstd-${LIBZSTD_VERSION} \
    && make \
    && make install \
    && cp /tmp/libszstd/zstd-${LIBZSTD_VERSION}/lib/libzstd.so.* /opt/lib/


# Fetch GDAL

RUN \
  mkdir -p /tmp/gdal \
  && curl -sfL https://github.com/OSGeo/gdal/archive/v${GDAL_VERSION}.tar.gz | tar zxf - -C /tmp/gdal --strip-components=2

# Build + install GDAL

WORKDIR /tmp/gdal

RUN \
  ./configure \
    --prefix=/opt \
    --datarootdir=/opt/share/gdal \
    --with-curl=/opt/bin/curl-config \
    --with-libtiff=internal \
    --with-crypto \
    --without-qhull \
    --without-mrf \
    --without-grib \
    --without-pcraster \
    --without-png \
    --without-gif \
    --with-jpeg=/opt \
    --without-pcidsk \
    --with-webp \
    --with-zstd && \
  make -j $(nproc) && \
  make -j $(nproc) install

# Install Python deps

WORKDIR /opt

ENV PYTHONPATH /opt/python
ENV GDAL_DATA=/opt/share/gdal

RUN \
  mkdir -p python && \
  pip3 install numpy Cython -t python/ && \
  pip3 install -U rasterio --no-binary rasterio -t python/

# delete build deps, symlinks, etc.
RUN find lib -name \*.la -delete
RUN find lib -name \*.a -delete
RUN find lib64 -name \*.la -delete
RUN find lib64 -name \*.a -delete
RUN rm -rf python/Cython*

# strip binaries
RUN strip bin/* || true
RUN find lib -name \*.so\* -exec strip {} \;
RUN find lib64 -name \*.so\* -exec strip {} \;
RUN find python -name \*.so\* -exec strip {} \;

RUN zip -r9q --symlinks /tmp/rasterio-layer.zip .

# unzip -v /tmp/whatever.zip | awk {'print $3 " " $8'} | sort -rn
