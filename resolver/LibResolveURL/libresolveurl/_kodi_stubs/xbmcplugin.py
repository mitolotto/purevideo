"""
Stub for the ``xbmcplugin`` Kodi module.

All functions are no-ops — plugin/directory operations are meaningless
outside of a running Kodi instance.
"""


def endOfDirectory(handle, succeeded=True, updateListing=False,
                   cacheToDisc=True):
    pass


def setContent(handle, content):
    pass


def addDirectoryItem(handle, url, listitem, isFolder=False, totalItems=0):
    return True


def addDirectoryItems(handle, items, totalItems=0):
    return True


def setResolvedUrl(handle, succeeded, listitem):
    pass


def getSetting(handle, id):
    return ""


def setSetting(handle, id, value):
    pass


def setPluginCategory(handle, category):
    pass


def setPluginFanArt(handle, image=None, color1=None, color2=None,
                    color3=None):
    pass
