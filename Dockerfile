FROM rocker/rstudio:4.6.1

# System libraries for building and running CRAN and Bioconductor packages.
# rocker/rstudio is minimal, and the p3m.dev binaries it installs from need
# the matching runtime libraries (e.g. libuv for fs). The -dev packages pull in
# the runtime libraries and also let packages compile from source.
#
# No R packages are installed here. They go in the persistent library that
# rstudio_apptainer.sbatch puts first on .libPaths().

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        gfortran \
        pkg-config \
        git \
        curl \
        wget \
        less \
        openssh-client \
        # compression and file formats
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libzstd-dev \
        libarchive-dev \
        libhdf5-dev \
        libnetcdf-dev \
        libxml2-dev \
        libxslt1-dev \
        libsqlite3-dev \
        libpcre2-dev \
        libicu-dev \
        # networking, crypto, async (curl, httr, fs, crew/mirai)
        libcurl4-openssl-dev \
        libssl-dev \
        libssh2-1-dev \
        libsodium-dev \
        libuv1-dev \
        libzmq3-dev \
        libgit2-dev \
        # databases
        libpq-dev \
        # math and statistics (igraph, nloptr, gmp, Rmpfr, RcppGSL, ...)
        libblas-dev \
        liblapack-dev \
        libfftw3-dev \
        libglpk-dev \
        libgmp-dev \
        libmpfr-dev \
        libgsl-dev \
        libnlopt-dev \
        libudunits2-dev \
        # graphics, fonts, images (ragg, systemfonts, Cairo, rgl)
        libcairo2-dev \
        libxt-dev \
        libx11-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff-dev \
        libwebp-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libpoppler-cpp-dev \
        # spatial (sf, terra, spatial Bioconductor packages)
        libgdal-dev \
        libgeos-dev \
        libproj-dev \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
