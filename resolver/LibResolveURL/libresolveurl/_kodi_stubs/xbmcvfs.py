"""
Stub for the ``xbmcvfs`` Kodi virtual filesystem module.

``special://`` path prefixes are translated to real filesystem paths under
``LIBRESOLVEURL_CONFIG_DIR`` (default: ``~/.config/libresolveurl``).

The ``special://xbmc/`` prefix maps to ``None`` so that callers like
``net.py`` which pass it as ``cafile=`` to ``ssl.create_default_context``
fall back to the system certificate store automatically.
"""
import logging
import os
import shutil

_logger = logging.getLogger("libresolveurl")

_CONFIG_DIR: str = os.environ.get(
    "LIBRESOLVEURL_CONFIG_DIR",
    os.path.join(os.path.expanduser("~"), ".config", "libresolveurl"),
)

# Map of special:// prefixes to real paths.
# Order matters — more specific prefixes first.
_SPECIAL: list = [
    ("special://profile/",        _CONFIG_DIR + os.sep),
    ("special://profile",         _CONFIG_DIR),
    ("special://masterprofile/",  _CONFIG_DIR + os.sep),
    ("special://masterprofile",   _CONFIG_DIR),
    ("special://userdata/",       _CONFIG_DIR + os.sep),
    ("special://userdata",        _CONFIG_DIR),
    ("special://home/",           _CONFIG_DIR + os.sep),
    ("special://home",            _CONFIG_DIR),
    ("special://temp/",           os.path.join(_CONFIG_DIR, "temp") + os.sep),
    ("special://temp",            os.path.join(_CONFIG_DIR, "temp")),
    ("special://logpath/",        _CONFIG_DIR + os.sep),
    ("special://logpath",         _CONFIG_DIR),
    # special://xbmc → Kodi installation dir, not available; return None
    # so ssl.create_default_context(cafile=None) uses system certs.
    ("special://xbmc",            None),
]


# ---------------------------------------------------------------------------
# Path translation
# ---------------------------------------------------------------------------

def translatePath(path):
    """Translate a ``special://`` Kodi path to a real filesystem path.

    Returns ``None`` for ``special://xbmc/`` paths (Kodi install dir) so
    that callers using the result as an SSL ``cafile`` fall back gracefully
    to system certificates.
    """
    if path is None:
        return None
    for prefix, replacement in _SPECIAL:
        if path.startswith(prefix):
            if replacement is None:
                return None
            return replacement + path[len(prefix):]
    return path


# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

def exists(path) -> bool:
    if not path:
        return False
    return os.path.exists(path)


def mkdirs(path) -> bool:
    if not path:
        return False
    try:
        os.makedirs(path, exist_ok=True)
        return True
    except Exception as exc:
        _logger.warning("xbmcvfs.mkdirs(%s) failed: %s", path, exc)
        return False


def mkdir(path) -> bool:
    return mkdirs(path)


def delete(path) -> bool:
    try:
        os.remove(path)
        return True
    except Exception:
        return False


def copy(source, destination) -> bool:
    try:
        shutil.copy2(source, destination)
        return True
    except Exception:
        return False


def rename(file, newFileName) -> bool:
    try:
        os.rename(file, newFileName)
        return True
    except Exception:
        return False


def listdir(path):
    """Return (dirs, files) tuple, mirroring the Kodi API."""
    try:
        entries = os.listdir(path)
        dirs = [e for e in entries if os.path.isdir(os.path.join(path, e))]
        files = [e for e in entries if os.path.isfile(os.path.join(path, e))]
        return dirs, files
    except Exception:
        return [], []


# ---------------------------------------------------------------------------
# File object
# ---------------------------------------------------------------------------

class File:
    """Thin wrapper around a regular file, matching the Kodi File API."""

    def __init__(self, path, mode="r"):
        self._fh = None
        if path:
            try:
                self._fh = open(path, mode)
            except Exception as exc:
                _logger.debug("xbmcvfs.File(%s, %r): %s", path, mode, exc)

    def read(self, numbytes=-1):
        if self._fh is None:
            return ""
        try:
            return self._fh.read() if numbytes == -1 else self._fh.read(numbytes)
        except Exception:
            return ""

    def write(self, data) -> bool:
        if self._fh is None:
            return False
        try:
            self._fh.write(data)
            return True
        except Exception:
            return False

    def close(self):
        if self._fh is not None:
            try:
                self._fh.close()
            except Exception:
                pass
            self._fh = None

    def size(self) -> int:
        if self._fh is None:
            return -1
        try:
            pos = self._fh.tell()
            self._fh.seek(0, 2)
            size = self._fh.tell()
            self._fh.seek(pos)
            return size
        except Exception:
            return -1

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
