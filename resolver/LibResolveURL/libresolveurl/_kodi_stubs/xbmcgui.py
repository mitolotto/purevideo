"""
Stub for the ``xbmcgui`` Kodi module.

All dialog and window classes are no-ops or auto-pick sensible defaults:
  - ``Dialog.select()``  → returns 0 (first item) so resolvers auto-choose
  - ``Dialog.yesno()``   → returns True
  - Progress dialogs     → silent no-ops
  - ListItem             → stores label for inspection if needed
"""
import logging

_logger = logging.getLogger("libresolveurl")

# ---------------------------------------------------------------------------
# Constants used by the upstream code
# ---------------------------------------------------------------------------
ALPHANUM_HIDE_INPUT = 1
INPUT_ALPHANUM = 0
INPUT_NUMERIC = 1
INPUT_DATE = 2
INPUT_TIME = 3
INPUT_IPADDRESS = 4
INPUT_PASSWORD = 5


# ---------------------------------------------------------------------------
# Dialogs
# ---------------------------------------------------------------------------

class Dialog:
    def yesno(self, heading, message="", line1="", line2="", line3="",
              nolabel="", yeslabel="", autoclose=0):
        return True

    def ok(self, heading, message="", line1="", line2="", line3=""):
        pass

    def notification(self, heading, message, icon="", time=5000, sound=True):
        _logger.info("Notification [%s]: %s", heading, message)

    def input(self, heading, defaultt="", type=INPUT_ALPHANUM,
              option=0, autoclose=0):
        return defaultt

    def select(self, heading, items, autoclose=0, preselect=-1,
               useDetails=False):
        """Auto-pick the first available item."""
        return 0 if items else -1

    def multiselect(self, heading, options, autoclose=0,
                    preselect=None, useDetails=False):
        return [0] if options else None

    def browse(self, type, heading, shares, mask="", useThumbs=False,
               treatAsFolder=False, defaultt="", enableMultiple=False):
        return defaultt

    def textviewer(self, heading, text, usemono=False):
        pass

    def contextmenu(self, items):
        return 0 if items else -1


class DialogProgress:
    def create(self, heading, message="", line1="", line2="", line3=""):
        pass

    def update(self, percent, message="", line1="", line2="", line3=""):
        pass

    def close(self):
        pass

    def iscanceled(self):
        return False


class DialogProgressBG:
    def create(self, heading, message=""):
        pass

    def update(self, percent=0, heading="", message=""):
        pass

    def close(self):
        pass

    def isFinished(self):
        return True


# ---------------------------------------------------------------------------
# ListItem  (used by create_item / add_item in kodi.py, not critical for lib)
# ---------------------------------------------------------------------------

class ListItem:
    def __init__(self, label="", label2="", iconImage="",
                 thumbnailImage="", path="", offscreen=False):
        self.label = label

    def setProperty(self, key, value):
        pass

    def setProperties(self, properties):
        pass

    def setInfo(self, type, infoLabels):
        pass

    def setArt(self, dictionary):
        pass

    def addContextMenuItems(self, items, replaceItems=False):
        pass

    def getLabel(self):
        return self.label

    def setSubtitles(self, subtitleFiles):
        pass

    def setMimeType(self, mimetype):
        pass

    def setContentLookup(self, enable):
        pass


# ---------------------------------------------------------------------------
# Window  (referenced in captcha_window.py)
# ---------------------------------------------------------------------------

class Window:
    def __init__(self, existingWindowId=-1):
        pass

    def show(self):
        pass

    def close(self):
        pass

    def doModal(self):
        pass

    def addControl(self, control):
        pass

    def removeControl(self, control):
        pass

    def setFocus(self, control):
        pass


class WindowXML(Window):
    def __init__(self, xmlFilename, scriptPath, defaultSkin="Default",
                 defaultRes="720p", isMedia=False):
        super().__init__()


class WindowXMLDialog(WindowXML):
    pass


# Alias used by recaptcha_v2.py and similar upstream files
class WindowDialog(Window):
    pass
