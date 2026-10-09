"""Shared compact native HUD layout, in Source's 480-height virtual pixels."""
X = 5
BOTTOM = 205
STRIDE = 49
WIDTH = 112
TOP_INSET = 2
HEIGHT = 60


def shader_header():
    # Retained owned include file for old installations, no world/hand cutouts.
    return '// Teammate HUD now uses the guest GUI alpha layer. No Source image masking.\n'
