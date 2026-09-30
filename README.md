# Run RStudio Server on the HTCF with Apptainer

RStudio Server on the HTCF needs two things sorted out: the compiled software
R relies on, and where R puts installed packages. A container handles the
first. A persistent library directory, bound in from the cluster filesystem,
handles the second: packages you install in one session are still there the
next time.

There is no Dockerfile in this repo. Build the base image with
[Seqera Containers](https://seqera.io/containers/) (or use any image you
like) and point the sbatch script at the resulting `.sif`.

## Image requirements

The image must contain **R and `rserver`** (RStudio Server). Check before you
submit anything:

```bash
apptainer exec <image>.sif bash -c 'command -v R; command -v rserver || ls /usr/lib/rstudio-server/bin/rserver'
```

Both need to print a path. Most conda-built images (which is what Seqera
Containers produces) do not ship `rserver`. If yours does not, use an image
that does, e.g. `apptainer pull docker://rocker/rstudio:4.5.3`.

## Get the image on the cluster

Either build one at Seqera Containers and download the `.sif`, or
`apptainer pull` a container from a registry. Put it somewhere shared, e.g.
under `/ref/` or `/lts/`.

## Launch

`/scratch`, `/lts`, `/home` and `/ref` are mounted into containers on the
HTCF, so no `-B` flags are needed for them. The persistent library is used at
its real path inside the container.

```bash
mkdir -p logs
sbatch rstudio_apptainer.sbatch \
    /path/to/image.sif \
    /ref/mblab/software/chasem/R/4.5.3
```

Override resources at submission if needed:

```bash
sbatch --cpus-per-task=8 --mem=32G --time=08:00:00 rstudio_apptainer.sbatch <sif> <libpath>
```

Arguments:

- `$1` path to the `.sif` image
- `$2` persistent library directory (must already exist, and be writable by you)

## Connect

Once the job starts, `logs/rstudio_<jobid>.out` contains an SSH tunnel command
and a `localhost` URL. Run the `ssh ... -N -L ...` command in a terminal on
your own machine, then open the URL. The server can take a short while to
respond after the log message appears.

## Set the persistent library (every session)

Setting the library through R config files (`.Rprofile`, `Renviron`) did not
work reliably inside the container, so it is set interactively instead.
**In the RStudio console, at the start of each session:**

```r
.libPaths(c("/ref/mblab/software/chasem/R/4.5.3", .libPaths()))
.libPaths()   # confirm your directory is listed first
```

Because the path is first, `install.packages()` and `BiocManager::install()`
write there, and packages already in it are found first. The image's own
packages stay available as a fallback. Use the same directory every session
and nothing needs reinstalling.

Notes:

- The directory must match the R version of the image (4.5.x here). Do not
  share one library between different R minor versions.
- Installing from source needs compilers. If a package fails to build, the
  image is likely missing them; add them to the image or install a binary.
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
