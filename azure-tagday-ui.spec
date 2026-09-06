# -*- mode: python ; coding: utf-8 -*-
import os
import sys

block_cipher = None

project_root = os.path.abspath(os.curdir)
src_dir = os.path.join(project_root, "src")

datas = [
    (os.path.join(src_dir, "gui", "qml"), os.path.join("gui", "qml")),
    (os.path.join(project_root, "templates"), "templates"),
    (os.path.join(project_root, "config"), "config"),
]

hiddenimports = [
    "PySide6.QtQml",
    "PySide6.QtQuick",
    "PySide6.QtQuickControls2",
    "PySide6.QtCore",
    "PySide6.QtGui",
    "PySide6.QtWidgets",
    "jinja2",
    "yaml",
    "dotenv",
    "docx",
    "sqlite3",
    "azure",
    "azure.azure_db",
    "azure.azure_info_handler",
    "azure.azure_info_base_client",
    "azure.azure_base_client",
    "azure.azure_helper",
    "gui",
    "gui.backend",
    "gui.workers",
    "utils",
    "generate_tagday_report",
    "generate_artifacts_report",
    "generate_revision",
    "devops_helper",
]

a = Analysis(
    [os.path.join(src_dir, "gui", "main.py")],
    pathex=[src_dir, project_root],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="azure-tagday-ui",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="azure-tagday-ui",
)
