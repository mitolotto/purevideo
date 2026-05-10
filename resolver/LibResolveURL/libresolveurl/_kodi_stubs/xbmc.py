"""
Stub for the ``xbmc`` Kodi module.

Provides the minimal surface used by ResolveURL so the addon code runs
outside of a Kodi environment.  All UI/media-player operations are no-ops;
logging is forwarded to Python's standard ``logging`` module.
"""
import logging
import time

# ---------------------------------------------------------------------------
# Log-level constants — mirror Kodi's values
# ---------------------------------------------------------------------------
LOGDEBUG = 0
LOGINFO = 1
LOGNOTICE = 1   # Kodi 18 alias; Python 2 compat kept by upstream
LOGWARNING = 2
LOGERROR = 4
LOGFATAL = 5

_logger = logging.getLogger("libresolveurl")

_LEVEL_MAP = {
    LOGDEBUG: logging.DEBUG,
    LOGINFO: logging.INFO,
    LOGNOTICE: logging.INFO,
    LOGWARNING: logging.WARNING,
    LOGERROR: logging.ERROR,
    LOGFATAL: logging.CRITICAL,
}


# ---------------------------------------------------------------------------
# Core functions
# ---------------------------------------------------------------------------

def log(msg, level=LOGDEBUG):
    _logger.log(_LEVEL_MAP.get(level, logging.DEBUG), msg)


def sleep(ms):
    time.sleep(ms / 1000.0)


def executebuiltin(cmd):
    """No-op: Kodi built-in commands are not available outside Kodi."""
    pass


def executeJSONRPC(command):
    """Returns an empty JSON-RPC response so callers don't crash."""
    return "{}"


def getInfoLabel(label):
    return ""


def getCondVisibility(condition):
    return False


def translatePath(path):
    """Kodi 18 (Leia) compat — delegate to xbmcvfs.translatePath."""
    import xbmcvfs  # noqa: PLC0415
    return xbmcvfs.translatePath(path)


def getSupportedMedia(media_type):
    if media_type == "video":
        return (
            ".mp4|.mkv|.avi|.mov|.wmv|.ts|.m2ts|.mpg|.mpeg"
            "|.flv|.webm|.m4v|.3gp|.ogv|.divx|.xvid|.m3u8|.strm"
        )
    if media_type == "music":
        return ".mp3|.flac|.ogg|.aac|.m4a|.wav|.wma"
    return ""


# ---------------------------------------------------------------------------
# Keyboard (used by kodi.get_keyboard_legacy)
# ---------------------------------------------------------------------------

class Keyboard:
    def __init__(self, heading="", hidden=False):
        self._text = ""
        self._confirmed = False

    def setHeading(self, heading):
        pass

    def setDefault(self, default):
        self._text = default

    def doModal(self):
        pass

    def isConfirmed(self):
        return self._confirmed

    def getText(self):
        return self._text
