"""The complete source code of a build, in one zip: this repository at its
current commit, with its submodules (the modified NetHack and Luanti,
external/nethack and external/luanti) at theirs.

NetHack's licence (dat/license, paragraph 3) lets a non-commercial release
point to where its source can be had, but a commercial one - VoxHack sold
on Steam - must come with the complete source: make_steam.py puts this zip
in the Steam build (source/). Made with `git archive`, so it holds exactly
what's committed; uncommitted changes are warned about (they'd be in the
game but not in the source).

    py -3 -I tools/make_source_archive.py <out.zip>
"""
import io
import os
import subprocess
import sys
import tarfile
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SUBMODULES = ['external/nethack', 'external/luanti']
TOP = 'VoxHack-source'

README = """VoxHack's source code
=====================

VoxHack-source.zip is the complete source of this build of VoxHack:

  (the top folder)   the game, its tools and the VoxHack core library
                     (github.com/MrEveryDay98/VoxHack, commit {main})
  external/nethack   NetHack 3.7, modified for VoxHack
                     (github.com/MrEveryDay98/NetHack, branch nhv, commit {nethack})
  external/luanti    the Luanti engine, modified for VoxHack
                     (github.com/MrEveryDay98/luanti, branch nhv, commit {luanti})

NetHack is free software under the NetHack General Public License
(external/nethack/dat/license); so is VoxHack, a work based on it. You may
copy, change and share it under that licence's terms. Luanti is under the
LGPL 2.1 or later (external/luanti/LICENSE.txt). CREDITS.md lists every
part and its licence.

Building it: see README.md (Windows, MSYS2 clang64).
"""


def git(path, *args):
    return subprocess.run(['git', '-C', os.path.join(ROOT, path)] + list(args),
                          capture_output=True, check=True).stdout


def add_tree(z, path, prefix):
    # (git archive's tar, written into the zip under prefix)
    tar = tarfile.open(fileobj=io.BytesIO(git(path, 'archive', '--format=tar', 'HEAD')))
    n = 0
    for m in tar:
        if not m.isfile():
            continue
        info = zipfile.ZipInfo(prefix + m.name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (m.mode & 0o777) << 16
        z.writestr(info, tar.extractfile(m).read())
        n += 1
    return n


def commit(path):
    return git(path, 'rev-parse', '--short', 'HEAD').decode().strip()


def main(out):
    dirty = []
    for path in ['.'] + SUBMODULES:
        # (but the block catalogue, which the game writes itself as it runs)
        changed = [line for line in git(path, 'status', '--porcelain', '--untracked-files=no',
                                        '--ignore-submodules').decode().splitlines()
                   if not line.endswith('mod_data/nhv/blocks_catalog.json')]
        if changed:
            dirty.append(path)
    if dirty:
        print('warning: uncommitted changes in %s - the source zip holds only what is committed'
              % ', '.join(dirty))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with zipfile.ZipFile(out, 'w', compresslevel=9) as z:
        n = add_tree(z, '.', TOP + '/')
        for sub in SUBMODULES:
            n += add_tree(z, sub, TOP + '/' + sub + '/')
    readme = README.format(main=commit('.'), nethack=commit(SUBMODULES[0]), luanti=commit(SUBMODULES[1]))
    with open(os.path.join(os.path.dirname(os.path.abspath(out)), 'README.txt'), 'w', encoding='utf-8',
              newline='\r\n') as f:
        f.write(readme)
    print('%s: %d files (%.1f MB)' % (out, n, os.path.getsize(out) / 1e6))


if __name__ == '__main__':
    main(sys.argv[1])
