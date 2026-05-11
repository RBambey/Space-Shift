# -*- mode: python ; coding: utf-8 -*-
import sys

is_mac = sys.platform == 'darwin'
icon = ['icon.icns'] if is_mac else ['icon.ico']

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('icon.png', '.')],
    hiddenimports=['rtmidi'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='MIDI Joy',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon,
)

if is_mac:
    app = BUNDLE(
        exe,
        name='MIDI Joy.app',
        icon='icon.icns',
        bundle_identifier='com.rbambey.midijoy',
    )
