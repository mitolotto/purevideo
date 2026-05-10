"""
libresolveurl — Python library wrapper for ResolveURL (Kodi addon fork).

Provides a clean, pip-installable interface to the ResolveURL resolver
engine without requiring a running Kodi installation.

Usage::

    import libresolveurl

    # Resolve an embed/hosting page to a direct stream URL
    url = libresolveurl.resolve("https://streamtape.com/v/xyz123")
    # → "https://..." or None

    # Fast check — no HTTP requests made
    ok = libresolveurl.is_supported("https://streamtape.com/v/xyz123")
    # → True

    # All domains that have a dedicated resolver
    domains = libresolveurl.get_supported_domains()
    # → ['1fichier.com', 'dailymotion.com', ...]

    # Configure API tokens for debrid services (persisted across sessions)
    libresolveurl.configure({
        "RealDebridResolver_token": "...",
        "RealDebridResolver_enabled": "true",
    })

Rebase note
-----------
All library code lives exclusively in ``libresolveurl/`` and
``pyproject.toml``.  The upstream addon tree (``script.module.resolveurl/``,
``script.module.resolveurl.xxx/``, ``plugin.video.smr_link_tester/``) is
**never modified**, so ``git rebase upstream/master`` is conflict-free.
"""
from __future__ import annotations

import logging
import os
import sys

__version__ = "0.1.0"
__all__ = ["resolve", "is_supported", "get_supported_domains", "configure"]

_log = logging.getLogger("libresolveurl")

# ---------------------------------------------------------------------------
# Bootstrap — must happen before any resolveurl / kodi_six import
# ---------------------------------------------------------------------------

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(_HERE)

# Upstream source directories
_RURL_LIB = os.path.normpath(
    os.path.join(_REPO_ROOT, "script.module.resolveurl", "lib")
)
_XXX_PLUGINS = os.path.normpath(
    os.path.join(
        _REPO_ROOT,
        "script.module.resolveurl.xxx",
        "resources",
        "plugins",
    )
)

# Kodi stub modules (our fake xbmc, xbmcaddon, kodi_six, …)
_STUBS = os.path.join(_HERE, "_kodi_stubs")

# Config dir: settings JSON + generated settings.xml land here, not in the
# git-tracked upstream tree.
_DEFAULT_CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "libresolveurl")

# Set env vars BEFORE the stubs are imported — stubs read them at module level.
if not os.environ.get("LIBRESOLVEURL_CONFIG_DIR"):
    os.environ.setdefault("LIBRESOLVEURL_CONFIG_DIR", _DEFAULT_CONFIG_DIR)
if not os.environ.get("LIBRESOLVEURL_ADDON_PATH"):
    os.environ.setdefault("LIBRESOLVEURL_ADDON_PATH", _DEFAULT_CONFIG_DIR)

# Evict any pre-installed kodi-six or real Kodi modules from sys.modules so
# our stubs take precedence unconditionally.
for _mod_name in ("xbmc", "xbmcaddon", "xbmcgui", "xbmcplugin", "xbmcvfs", "kodi_six"):
    sys.modules.pop(_mod_name, None)

# Inject stubs FIRST so that `import xbmc` (and `from kodi_six import …`)
# resolves to our shims.
if _STUBS not in sys.path:
    sys.path.insert(0, _STUBS)

# Inject upstream resolveurl source so that `import resolveurl` works.
if _RURL_LIB not in sys.path:
    sys.path.insert(0, _RURL_LIB)

# ---------------------------------------------------------------------------
# Import upstream resolveurl
# ---------------------------------------------------------------------------

import resolveurl as _rurl  # noqa: E402
from resolveurl.hmf import HostedMediaFile as _HMF  # noqa: E402
from resolveurl.lib import kodi as _kodi  # noqa: E402

# ---------------------------------------------------------------------------
# Load XXX extension (optional — present only when the subdir exists)
# ---------------------------------------------------------------------------

if os.path.isdir(_XXX_PLUGINS):
    _rurl.add_plugin_dirs(_XXX_PLUGINS)
    _rurl.load_external_plugins()
    _log.debug("libresolveurl: loaded XXX extension from %s", _XXX_PLUGINS)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def resolve(url: str) -> str | None:
    """Resolve a hosting/embed page URL to a direct media stream URL.

    Iterates all matching resolver plugins in priority order.  For each one
    it fetches/scrapes/decodes the page and validates the resulting stream
    with a lightweight HTTP Range request.

    Args:
        url: Full URL of the embed or hosting page.

    Returns:
        A direct stream URL string on success, or ``None`` if no resolver
        could handle the URL or all attempts failed.

    Example::

        url = libresolveurl.resolve("https://streamtape.com/v/abc123")
        if url:
            print("Stream:", url)
        else:
            print("Could not resolve")
    """
    try:
        result = _rurl.resolve(url)
        return result if result else None
    except Exception as exc:
        _log.error("resolve(%s) raised: %s", url, exc)
        return None


def is_supported(url: str) -> bool:
    """Return ``True`` if at least one resolver plugin can handle *url*.

    This is a **fast, offline check** — no HTTP requests are made.  It only
    verifies that a plugin's domain list or URL pattern matches the given URL.

    Args:
        url: URL to test.

    Returns:
        ``True`` if the URL is supported, ``False`` otherwise.

    Example::

        if libresolveurl.is_supported(link):
            direct = libresolveurl.resolve(link)
    """
    try:
        hmf = _HMF(url=url, include_disabled=True)
        return bool(hmf)
    except Exception:
        return False


def get_supported_domains() -> list[str]:
    """Return a sorted list of all domains that have a dedicated resolver.

    Universal resolvers (debrid services that handle ``domains=['*']``) are
    excluded — they accept any domain and are not domain-specific.

    Returns:
        Alphabetically sorted list of domain strings, e.g.
        ``['1fichier.com', 'dailymotion.com', 'streamtape.com', …]``.

    Example::

        domains = libresolveurl.get_supported_domains()
        print(f"{len(domains)} domains supported")
    """
    resolvers = _rurl.relevant_resolvers(
        include_universal=False,
        include_disabled=True,
        include_popups=True,
    )
    domains: set[str] = set()
    for resolver in resolvers:
        for domain in resolver.domains:
            if domain and domain != "*":
                domains.add(domain.lower())
    return sorted(domains)


def configure(settings: dict) -> None:
    """Persist resolver settings (API tokens, feature flags, …).

    Values are written immediately to
    ``~/.config/libresolveurl/settings.json`` and are read back
    automatically by resolver plugins on next use — no restart required.

    Common setting keys::

        # Real-Debrid
        RealDebridResolver_token    — OAuth token
        RealDebridResolver_enabled  — "true" / "false"

        # AllDebrid
        AllDebridResolver_token     — API key
        AllDebridResolver_enabled   — "true" / "false"

        # Premiumize.me
        PremiumizeMeResolver_token  — API key
        PremiumizeMeResolver_enabled — "true" / "false"

        # Generic resolver priority (lower = higher priority, default 100)
        StreamtapeResolver_priority — "50"

    Args:
        settings: Mapping of setting key → value (both strings).

    Example::

        libresolveurl.configure({
            "RealDebridResolver_token": "MY_TOKEN",
            "RealDebridResolver_enabled": "true",
        })
    """
    for key, value in settings.items():
        _kodi.set_setting(key, str(value))
