# Run RStudio Server on the HTCF with Spack

This repo runs RStudio Server on the HTCF from a Spack environment in a slurm 
job. The environment provides RStudio Server, R, and the system
libraries (headers and shared libraries) that R packages need to build from
source. Because it runs on the host, Slurm commands such as `sbatch` and
`squeue` are available in the RStudio terminal, which means you can use 
packages like [targets](https://books.ropensci.org/targets/),
[crew.cluster](https://wlandau.github.io/crew.cluster/) and
[future.batchtools](future.batchtools.futureverse.org) that
submit jobs to Slurm, and easily monitor and ingest the results.

Using those tools help, because for jobs that require more resources,
it makes it easy to submit it to the cluster. Those resources will 
be used for that job, and then exited. However, rstudio still does 
run on in the interactive node (or it should. that is how the sbatch 
script is set up). If you aren't actively using rstudio, exit the 
session and free up those resources for someone else.

There are three parts:

1. [Create the Spack environment](#1-create-the-spack-environment) (once).
2. [Launch an interactive RStudio session](#2-launch-an-interactive-rstudio-session).
3. [Use the environment in batch jobs](#3-use-the-environment-in-batch-jobs)
   that call `Rscript`.

Read [Limitations](#limitations) before installing packages.

## 1. Create the Spack environment

**Register the recipe repo.** The `rstudio-server` package recipe is in
`spack/spack_repo/brentlab`:

```bash
spack repo add /path/to/spack/spack_repo/brentlab
```

If `spack repo add` complains that the `repos` section is in a deprecated
format, update it with `spack config --scope <scope> update repos` (find the
scope with `spack config blame repos`). Older Spack versions cannot read the
updated file, so check before changing a config that is shared.

**Copy the environment to a stable location.** The environment is
`spack/env/spack.yaml`. Installing creates a `view/` directory inside the
environment directory that holds links to everything, and jobs use it, so put
the environment somewhere that will not be cleaned up (not a purged scratch
directory):

```bash
cp -r spack/env /ref/mblab/software/<you>/rstudio-env
```

**Install it.** Do this on a node running the OS you will run jobs on (see
the notes on the package below). Concretizing first checks the specs; the
install builds the libraries from source and is slow, so run it in a job or a
`tmux` session with a long time limit. In one install, building `cmake` alone
took about 35 minutes:

```bash
spack -e /ref/mblab/software/<you>/rstudio-env concretize -f
spack -e /ref/mblab/software/<you>/rstudio-env install
```

To change what is in the environment, edit its `spack.yaml` and install
again:

- **R version:** change the `r@4.6.1` line.
- **More libraries:** add specs. The spatial and HDF5 libraries (`hdf5`,
  `netcdf-c`, `gdal`, `geos`, `proj`) are commented out because they take a
  long time to build; uncomment them if you need `sf`, `terra`, `hdf5r` and so
  on.

Keep one environment directory per R version if you need more than one.

Notes on the `rstudio-server` package:

- It installs RStudio Server from Posit's prebuilt RPM (nothing is compiled)
  and unpacks it with `bsdtar` (a build dependency, `libarchive`).
- The EL8 and EL9 RPMs are different builds, so the package picks the one that
  matches the OS Spack is running on (`...-el8` or `...-el9`). The HTCF login
  node and the compute nodes can run different OS releases, so install on a
  node of the OS you will run on.
- It depends on R at run time, and the R version is part of the install.
- It is about 740 MB installed. The GitHub Copilot language server (about
  800 MB more) is left out unless you install with `+copilot`.
- Spack stages the RPM (about 400 MB) and unpacks it (about 1.6 GB) while
  installing. If the default staging location is too small, set
  `config:build_stage` to a directory on `/scratch`.

## 2. Launch an interactive RStudio session

```bash
mkdir -p logs
sbatch rstudio_spack.sbatch /ref/mblab/software/<you>/rstudio-env
```

The argument is the environment directory. If you leave it out, the script
uses `spack/env` under the directory you submit from. Override resources at
submission if needed:

```bash
sbatch --cpus-per-task=8 --mem=32G --time=08:00:00 rstudio_spack.sbatch <env_dir>
```

The `spack` command must be on your `PATH` when you submit. The script
activates the environment for the job and puts its libraries on the compiler
and loader paths, so packages installed from source in the RStudio session
find the environment's headers and libraries.

**Connect.** Once the job starts, `logs/rstudio_<jobid>.out` contains an SSH
tunnel command and a `localhost` URL. Run the `ssh ... -N -L ...` command in a
terminal on your own machine, then open the URL. The server can take a short
while to respond after the log message appears.

**Sessions are not kept between jobs.** RStudio normally stores session state
(the running or suspended R session, history, open editor tabs) in
`~/.local/share/rstudio`, and a new job would resume it. The script instead
sets `RSTUDIO_DATA_HOME` to a per-job temp directory that is deleted when the
job ends, so every launch starts a fresh session. Save anything you want to
keep (scripts, data) to a real directory; unsaved editor tabs, history and
the R workspace do not survive a relaunch. RStudio preferences
(`~/.config/rstudio`) are unaffected.

## 3. Use the environment in batch jobs

Packages you installed from RStudio are in the Spack R's library and the
compiled ones link against libraries in the environment. A batch job that
calls `Rscript` therefore has to activate the environment and put its
libraries on `LD_LIBRARY_PATH`, the same as the launcher does:

```bash
#!/bin/bash
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G

env=/ref/mblab/software/<you>/rstudio-env

eval "$(spack env activate --sh "$env")"
export LD_LIBRARY_PATH="$env/view/lib:$env/view/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

Rscript my_script.R
```

Why `LD_LIBRARY_PATH` is needed: compiled R packages carry no link to the
environment's libraries, so without it a package such as `curl` can fail to
load (`libcurl.so.4: cannot open shared object file`) or pick up a different
system library. Activating the environment alone sets `PATH` and
`PKG_CONFIG_PATH`, but not this.

If you only need R and pure-R packages (nothing compiled against the
environment's libraries), `eval "$(spack load --sh r@4.6.1)"` is enough, but
the environment is the safe choice.

For workers started by `crew.cluster` (or any tool that submits its own Slurm
jobs), add the same lines to the worker's job script. In `crew.cluster` that is
the `script_lines` option of `crew_options_slurm()`; check its documentation
for the exact argument.

## Limitations

- **Packages go into the spack R library, which may be shared.** If you are
  using a spack location that is shared by more than one user, the
  environment does not set up a per-user library. `install.packages()`
  and `BiocManager::install()` write into the library of the Spack R
  install, for example `/ref/mblab/software/spack-1.1.0/opt/spack/linux-x86_64/r-4.6.1-<hash>/rlib/R/library`.
  Anyone using that same R install shares those packages: what you install is
  visible to them, and a newer version installed by someone else changes what
  you get. The packages are also lost if that R is uninstalled or reinstalled.
  If you want your own library, set it yourself with
  `.libPaths(c("/path/to/my/library", .libPaths()))` at the start of each
  session (the directory must already exist). This repo does not configure it.
- **You must use the environment to use the packages.** Packages built from
  RStudio depend on the environment's libraries, so batch jobs need the
  environment activated as in [section 3](#3-use-the-environment-in-batch-jobs).
- **Do not mix library builds.** Compiled packages link against libraries
  from where they were built. Do not share a package library between this
  environment and a different R or a different host, even at the same R
  version.
- **Rocky 8 versus Rocky 9.** The environment is built for the OS it was
  installed on. Install it on, and run it on, the same OS release.
- **Bioconductor.** `BiocManager::install()` builds from source and uses the
  environment's libraries; add any missing system library to `spack.yaml`.

## Credit

Adapted from David Tang's post on running RStudio Server with Docker:
<https://davetang.org/muse/2021/04/24/running-rstudio-server-with-docker/>
