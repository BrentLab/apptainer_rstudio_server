# Run RStudio Server on the HTCF with Apptainer

RStudio Server on the HTCF needs two things sorted out: the compiled software
R relies on, and where R puts installed packages. A container handles the
first. A persistent library directory, bound in from the cluster filesystem,
handles the second: packages you install in one session are still there the
next time.

The `Dockerfile` in this repo builds on `rocker/rstudio:4.6.1` and adds the
system libraries needed to run and compile CRAN and Bioconductor packages
(libuv, libcurl, libxml2, hdf5, graphics and font libraries, GDAL/GEOS/PROj,
and more). No R packages are baked in; they live in the persistent library.

The stock `rocker/rstudio` image is minimal. R installs precompiled binaries
from Posit Package Manager, and those need matching system libraries at run
time. Without them, packages fail to load, e.g. `fs`:
`libuv.so.1: cannot open shared object file`.

## Build the image

On a machine with Docker:

```bash
docker build -t <dockerhub username>/rstudio-bioc:4.6.1 .
docker push <dockerhub username>/rstudio-bioc:4.6.1
```

## Get the image on the cluster

```bash
apptainer pull rstudio_bioc_4.6.1.sif docker://<dockerhub username>/rstudio-bioc:4.6.1
```

Put the `.sif` somewhere shared, e.g. under `/ref/` or `/lts/`.

To confirm the image has what the sbatch script needs:

```bash
apptainer exec rstudio_bioc_4.6.1.sif bash -c 'R --version | head -1; command -v rserver || ls /usr/lib/rstudio-server/bin/rserver; ldconfig -p | grep libuv'
```

Any other image works if it contains both R and `rserver`, but may lack the
system libraries above.

## Launch

`/scratch`, `/lts`, `/home` and `/ref` are mounted into containers on the
HTCF, so no `-B` flags are needed for them.

```bash
mkdir -p logs
sbatch rstudio_apptainer.sbatch \
    /ref/mblab/containers/chasem/rstudio_bioc_4.6.1.sif \
    /ref/mblab/software/chasem/R-rstudio
```

Override resources at submission if needed:

```bash
sbatch --cpus-per-task=8 --mem=32G --time=08:00:00 rstudio_apptainer.sbatch <sif> <lib_base_dir>
```

Arguments:

- `$1` path to the `.sif` image
- `$2` base directory for persistent R libraries (must already exist, and be
  writable by you). A per-R-version subdirectory is created inside it.

## Connect

Once the job starts, `logs/rstudio_<jobid>.out` contains an SSH tunnel command
and a `localhost` URL. Run the `ssh ... -N -L ...` command in a terminal on
your own machine, then open the URL. The server can take a short while to
respond after the log message appears.

## Persistent library

The sbatch script works out the image's R version (e.g. `4.6`), creates
`<lib_base_dir>/4.6`, and starts `rserver` with a small `rsession` wrapper
that exports `R_LIBS=<lib_base_dir>/4.6` before running the real `rsession`.
(rserver does not pass its own environment to R sessions, so exporting the
variable in the job script is not enough.) `R_LIBS` is used rather than
`R_LIBS_USER` because rocker images set `R_LIBS` to the read-only system
library, which would otherwise stay first. Nothing is added to `$HOME`, so
other R runs are unaffected. Check with `.libPaths()`: your directory should
be listed first, followed by the image's own libraries.

Because the path is first, `install.packages()` and `BiocManager::install()`
write there, and packages already in it are found first. The image's own
packages stay available as a fallback. Use the same base directory every
session and nothing needs reinstalling.

Notes:

- **Do not share a library directory between different images or hosts, even
  at the same R version.** Compiled packages link against system libraries
  (e.g. `libuv`) that exist only where they were built. A package built
  elsewhere, or against a different image, can fail to load with an error like
  `unable to load shared object '.../fs/libs/fs.so': libuv.so.1: cannot open
  shared object file`. Use a separate base directory per image, and a new one
  when you switch to a rebuilt image.
- Each R major.minor version gets its own subdirectory (`.../R/4.6`), so
  upgrading the image does not mix libraries.
- Installing from source needs compilers. If a package fails to build, the
  image is likely missing a system library; add it to the `Dockerfile` and
  rebuild.
- If installs fail with "not writable", check that you can `touch` a file in
  the directory from inside the container.

## Security note

`rserver` is started without authentication and listens on the compute node,
as in the original version of this repo. Anyone who can reach that node's
port can open a session as you. Keep sessions short and cancel the job
(`scancel <jobid>`) when you are done.

## Credit

Adapted from David Tang's post on running RStudio Server with Docker:
<https://davetang.org/muse/2021/04/24/running-rstudio-server-with-docker/>
