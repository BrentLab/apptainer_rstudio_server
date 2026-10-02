# Spack recipe for RStudio Server (open source edition), installed from the
# prebuilt RPMs that Posit publishes. Nothing is compiled.
#
# The EL8 and EL9 RPMs are different builds (the EL8 one needs OpenSSL 1.1,
# the EL9 one needs OpenSSL 3), so each release is listed twice and the
# matching one is forced by the OS the spec is concretized for.

import os
import shutil

from spack_repo.builtin.build_systems.generic import Package

from spack.package import *

_BASE = "https://download2.rstudio.org/server"

# release -> {EL major version: sha256 of the RPM}
_RELEASES = {
    "2026.09.0-174": {
        "el8": "f03e64f21b8d6579944976756459af072e22a43238934d76618fb1d2608344fb",
        "el9": "dfeecfb9737b5b5665bf37d2d5fb94f0584509fb559a0aeef54c22e61993b013",
    }
}

# Spack OS names for each RPM flavor.
_OS = {
    "el8": ("rhel8", "rocky8", "almalinux8", "centos8"),
    "el9": ("rhel9", "rocky9", "almalinux9"),
}


class RstudioServer(Package):
    """RStudio Server, the browser-based IDE for R, from Posit's prebuilt RPMs.

    This is the server only (rserver, rsession); R itself is a separate
    dependency. It is intended for running rserver as an unprivileged user,
    e.g. inside a Slurm job, not as a system service."""

    homepage = "https://posit.co/products/open-source/rstudio-server/"

    license("AGPL-3.0-only")

    for _rel, _sums in _RELEASES.items():
        for _el, _sha in _sums.items():
            version(
                f"{_rel}-{_el}",
                url=f"{_BASE}/rhel{_el[2:]}/x86_64/rstudio-server-rhel-"
                f"{_rel}-x86_64.rpm",
                sha256=_sha,
                expand=False,
            )
            # Each RPM only runs on its own EL generation.
            _other = "el9" if _el == "el8" else "el8"
            for _os in _OS[_other]:
                conflicts(f"os={_os}", when=f"@{_rel}-{_el}")

    variant(
        "copilot",
        default=False,
        description="Keep the GitHub Copilot language server (about 800 MB)",
    )

    depends_on("r@4:", type="run")

    # bsdtar unpacks the RPM (its payload is zstd-compressed cpio).
    depends_on("libarchive programs=bsdtar compression=zstd", type="build")

    def install(self, spec, prefix):
        bsdtar = which("bsdtar", required=True)
        bsdtar("-xf", self.stage.archive_file)

        libdir = join_path(prefix.lib, "rstudio-server")
        mkdirp(prefix.lib)
        install_tree(join_path("usr", "lib", "rstudio-server"), libdir)

        if "~copilot" in spec:
            copilot = join_path(libdir, "bin", "copilot-language-server-js")
            if os.path.isdir(copilot):
                shutil.rmtree(copilot)
            elif os.path.exists(copilot):
                os.remove(copilot)

        mkdirp(prefix.bin)
        for exe in ("rserver", "rsession", "rpostback", "r-ldpath"):
            os.symlink(join_path(libdir, "bin", exe), join_path(prefix.bin, exe))

    def setup_run_environment(self, env):
        env.set("RSTUDIO_SERVER_HOME", join_path(self.prefix.lib, "rstudio-server"))
