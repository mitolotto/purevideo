"""
Stub for the ``kodi_six`` compatibility package.

kodi-six normally wraps the real Kodi API modules with Python 2/3 shims.
Here we simply re-export our own stub modules so that:

    from kodi_six import xbmc, xbmcaddon, xbmcgui, xbmcplugin, xbmcvfs

works transparently.  The stubs directory is on sys.path when this module
is imported, so plain ``import xbmc`` resolves to our xbmc.py stub.
"""
import xbmc          # noqa: F401
import xbmcaddon     # noqa: F401
import xbmcgui       # noqa: F401
import xbmcplugin    # noqa: F401
import xbmcvfs       # noqa: F401
