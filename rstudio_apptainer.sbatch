#!/bin/bash
#SBATCH --job-name=rstudio
#SBATCH --output=logs/rstudio_%j.out
#SBATCH --error=logs/rstudio_%j.err
#SBATCH --partition=interactive
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00

# Launch RStudio Server from an Apptainer image on the HTCF.
#
# usage (from a directory that contains a logs/ subdirectory):
#   sbatch rstudio_apptainer.sbatch <image.sif> <lib_base_dir>
#
# $1  path to the .sif image. It must contain both R and rserver.
# $2  base directory for persistent R libraries (must already exist and be
#     writable). A subdirectory per R major.minor version (e.g. 4.6) is
#     created inside it and set as R_LIBS for the RStudio sessions, so
#     it is first on .libPaths() and nothing needs to be added to $HOME.
#
# /scratch, /lts, /home and /ref are mounted into containers on the HTCF,
# so the lib base dir is visible inside the container at the same path.

set -euo pipefail

sif=${1:?usage: sbatch rstudio_apptainer.sbatch <image.sif> <lib_base_dir>}
libbase=${2:?usage: sbatch rstudio_apptainer.sbatch <image.sif> <lib_base_dir>}

# ------ Sanity checks ------
if [ -z "${SLURM_JOBID:-}" ]; then
    echo "Error: must be run as a job (use sbatch)" >&2
    exit 1
fi
if ! command -v apptainer >/dev/null 2>&1; then
    echo "Error: apptainer not found on PATH" >&2
    exit 1
fi
if [ ! -f "$sif" ]; then
    echo "Error: image not found: $sif" >&2
    exit 1
fi
if [ ! -d "$libbase" ]; then
    echo "Error: lib base dir does not exist: $libbase (mkdir it first)" >&2
    exit 1
fi

# ------ Find rserver and R inside the image ------
# rserver is resolved to its real path: rsession lives next to it, but not next
# to a symlink (e.g. /usr/local/bin/rserver in rocker images).
rserver=$(apptainer exec "$sif" bash -c \
    'readlink -f "$(command -v rserver)" || ls /usr/lib/rstudio-server/bin/rserver' 2>/dev/null || true)
if [ -z "$rserver" ]; then
    echo "Error: rserver not found in $sif -- this image cannot run RStudio Server" >&2
    exit 1
fi
rbin=$(apptainer exec "$sif" which R)

# Keep host R settings from leaking into the container's R
unset R_LIBS R_LIBS_USER R_LIBS_SITE XDG_RUNTIME_DIR

# ------ Per-job scratch space for rserver ------
port=$(shuf -i9000-9999 -n1)
host=$(hostname)
RSTUDIO_TMP=/tmp/rstudio-$USER-$SLURM_JOBID
mkdir -p "$RSTUDIO_TMP"/{data,db,run,var-lib}
trap 'rm -rf "$RSTUDIO_TMP"' EXIT

cat > "$RSTUDIO_TMP/rstudio-database.conf" <<DBCONF
provider=sqlite
directory=$RSTUDIO_TMP/db
DBCONF

# Per-version library directory. R ignores a library path that does not exist,
# so create it now.
rver=$(apptainer exec "$sif" Rscript -e 'cat(R.version$major, sub("\\..*", "", R.version$minor), sep = ".")')
libdir="$libbase/$rver"
mkdir -p "$libdir"

# rserver launches rsession with a cleaned environment, so variables exported
# here would not reach R. This wrapper sets R_LIBS and then runs the real
# rsession. R_LIBS (not R_LIBS_USER) is used because rocker images set R_LIBS to
# the read-only system library in Renviron.site unless it is already set, and
# R_LIBS_USER would sort after it.
cat > "$RSTUDIO_TMP/rsession.sh" <<RSESSION
#!/bin/bash
export R_LIBS="$libdir"
exec "$(dirname "$rserver")/rsession" "\$@"
RSESSION
chmod +x "$RSTUDIO_TMP/rsession.sh"

echo -e "
R library for this session: $libdir

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
apptainer exec \
    -B "$RSTUDIO_TMP" \
    -B "$RSTUDIO_TMP/run:/run" \
    -B "$RSTUDIO_TMP/var-lib:/var/lib/rstudio-server" \
    "$sif" \
    "$rserver" \
    --www-port "$port" \
    --secure-cookie-key-file "$RSTUDIO_TMP/secure-cookie-key" \
    --server-data-dir "$RSTUDIO_TMP/data" \
    --server-pid-file "$RSTUDIO_TMP/rstudio.pid" \
    --database-config-file "$RSTUDIO_TMP/rstudio-database.conf" \
    --rsession-path "$RSTUDIO_TMP/rsession.sh" \
    --rsession-which-r "$rbin" \
    --server-user "$USER"
