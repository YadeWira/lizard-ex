#!/usr/bin/env python3
"""Create a reproducible .tar.gz from a directory.

Usage:  make_archive.py <directory> <output.tar.gz> <epoch>

The same directory and epoch always produce the same bytes: entries are
sorted, every timestamp is the epoch, and the owner and group are zero.  Used
instead of "tar" because the GNU options that do this (--sort, --mtime,
--owner) do not exist in the bsdtar that macOS ships.

The mode bits are taken from the files, which is what makes the program inside
the archive executable.
"""

import gzip
import os
import sys
import tarfile


def main(argv):
    if len(argv) != 4:
        print("usage: make_archive.py <directory> <output.tar.gz> <epoch>", file=sys.stderr)
        return 2

    src, out, epoch = argv[1], argv[2], int(argv[3])
    if not os.path.isdir(src):
        print("error: %s is not a directory" % src, file=sys.stderr)
        return 1

    parent = os.path.dirname(os.path.abspath(src))

    def arcname(path):
        return os.path.relpath(os.path.abspath(path), parent)

    paths = [src]
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in dirs + files:
            paths.append(os.path.join(root, name))
    paths.sort()

    with open(out, "wb") as raw:
        # mtime 0 in the gzip header as well, or the archive still changes.
        with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=epoch) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tf:
                for path in paths:
                    info = tf.gettarinfo(path, arcname=arcname(path))
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    info.mtime = epoch
                    if info.isreg():
                        with open(path, "rb") as f:
                            tf.addfile(info, f)
                    else:
                        tf.addfile(info)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
