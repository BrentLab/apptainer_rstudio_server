#!/bin/bash
#SBATCH --job-name=rstudio
#SBATCH --output=logs/rstudio_%j.out
#SBATCH --error=logs/rstudio_%j.err
#SBATCH --partition=interactive
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00

# Launch RStudio Server from a Spack environment on the HTCF.
#
# usage (from the repo directory, which must contain a logs/ subdirectory):
#   sbatch rstudio_spack.sbatch [spack_env_dir]
#
# $1  optional Spack environment directory (default: spack/env under the
#     directory you submit from). It must already be installed:
#       spack -e <spack_env_dir> install
#     The R version comes from the environment: edit the r@ line in its
#     spack.yaml (e.g. r@4.6.1) and reinstall to change it, or keep one
#     environment per R version and pass the one you want here.
#
# The environment's view puts RStudio Server, R and the system libraries for
# building R packages (headers, pkg-config files, shared libraries) on PATH,
# the compiler paths and LD_LIBRARY_PATH for R sessions.
#
# Packages installed from RStudio go into the R library of the Spack R install,
# which is shared by everyone using that install. See the README.
#
# The 'spack' command must be on PATH.

set -euo pipefail

envdir=${1:-${SLURM_SUBMIT_DIR:-$PWD}/spack/env}
view="$envdir/view"

# ------ Sanity checks ------
if [ -z "${SLURM_JOBID:-}" ]; then
    echo "Error: must be run as a job (use sbatch)" >&2
    exit 1
fi
if ! command -v spack >/dev/null 2>&1; then
    echo "Error: spack not found on PATH" >&2
    exit 1
fi
if [ ! -f "$envdir/spack.yaml" ]; then
    echo "Error: no spack.yaml in spack env dir: $envdir" >&2
    exit 1
fi
if [ ! -d "$view" ]; then
    echo "Error: $view not found; install the environment first: spack -e $envdir install" >&2
    exit 1
fi

# ------ Activate the Spack environment ------
eval "$(spack env activate --sh "$envdir")"
# Make the view's headers and libraries visible to compilers and the loader, so
# R packages built from source find them and can load them. spack env activate
# sets PATH, PKG_CONFIG_PATH and CMAKE_PREFIX_PATH but not these.
export CPATH="$view/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$view/lib:$view/lib64${LIBRARY_PATH:+:$LIBRARY_PATH}"
export LD_LIBRARY_PATH="$view/lib:$view/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if ! command -v rserver >/dev/null 2>&1 || ! command -v R >/dev/null 2>&1; then
    echo "Error: rserver and R not both found after activating $envdir" >&2
    exit 1
fi
# rsession lives next to the real rserver, not next to the symlink in bin/
rserver=$(readlink -f "$(command -v rserver)")
rbin=$(command -v R)

# Keep host R settings from leaking into R
unset R_LIBS R_LIBS_USER R_LIBS_SITE XDG_RUNTIME_DIR

# ------ Per-job scratch space for rserver ------
port=$(shuf -i9000-9999 -n1)
host=$(hostname)
RSTUDIO_TMP=/tmp/rstudio-$USER-$SLURM_JOBID
mkdir -p "$RSTUDIO_TMP"/{data,db,rstudio-data}
trap 'rm -rf "$RSTUDIO_TMP"' EXIT

# Keep RStudio's per-user state (session metadata, suspended R state, history,
# open tabs) in the per-job directory instead of ~/.local/share/rstudio, so a
# new job never resumes a previous job's session. (Preferences stay in
# ~/.config/rstudio.)
export RSTUDIO_DATA_HOME="$RSTUDIO_TMP/rstudio-data"

cat > "$RSTUDIO_TMP/rstudio-database.conf" <<DBCONF
provider=sqlite
directory=$RSTUDIO_TMP/db
DBCONF

# rserver only lets us choose the rsession command, so this wrapper passes on
# the environment's paths. R sessions can then build and load packages that
# need the environment's libraries.
cat > "$RSTUDIO_TMP/rsession.sh" <<RSESSION
#!/bin/bash
export RSTUDIO_DATA_HOME="$RSTUDIO_TMP/rstudio-data"
export PATH="$PATH"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}"
export CPATH="$CPATH"
export LIBRARY_PATH="$LIBRARY_PATH"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
exec "$(dirname "$rserver")/rsession" "\$@"
RSESSION
chmod +x "$RSTUDIO_TMP/rsession.sh"

echo -e "
Spack environment: $envdir

In a local terminal, create an SSH tunnel to $host
-----------------------------------------------------------------
ssh $USER@login.htcf.wustl.edu -N -L $port:$host:$port
-----------------------------------------------------------------
Then open this address in a web browser
-----------------------------------------------------------------
http://localhost:$port
-----------------------------------------------------------------
It can take a moment after this message before the server responds.
"

# ------ Launch RStudio Server ------
"$rserver" \
    --www-port "$port" \
    --secure-cookie-key-file "$RSTUDIO_TMP/secure-cookie-key" \
    --server-data-dir "$RSTUDIO_TMP/data" \
    --server-pid-file "$RSTUDIO_TMP/rstudio.pid" \
    --database-config-file "$RSTUDIO_TMP/rstudio-database.conf" \
    --rsession-path "$RSTUDIO_TMP/rsession.sh" \
    --rsession-ld-library-path "$view/lib:$view/lib64" \
    --rsession-which-r "$rbin" \
    --server-user "$USER"
