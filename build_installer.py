# -*- coding: UTF-8 -*-
"""
Automation script to build PyInstaller bundle and Windows Installer (NSIS or Inno Setup).
"""
import os
import sys
import shutil
import subprocess
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("build_installer")


def find_nsis():
    """Locate makensis executable."""
    nsis = shutil.which("makensis")
    if nsis:
        return nsis
    default_paths = [
        r"C:\Program Files (x86)\NSIS\makensis.exe",
        r"C:\Program Files\NSIS\makensis.exe",
    ]
    for p in default_paths:
        if os.path.exists(p):
            return p
    return None


def find_inno_setup():
    """Locate ISCC (Inno Setup Compiler) executable."""
    iscc = shutil.which("ISCC")
    if iscc:
        return iscc
    default_paths = [
        r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        r"C:\Program Files\Inno Setup 6\ISCC.exe",
        r"C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
    ]
    for p in default_paths:
        if os.path.exists(p):
            return p
    return None


def run_command(cmd, desc):
    logger.info(f"==> {desc}...")
    logger.info(f"Executing: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    res = subprocess.run(cmd, check=True)
    if res.returncode != 0:
        logger.error(f"{desc} failed with return code {res.returncode}")
        sys.exit(res.returncode)
    logger.info(f"[OK] {desc} succeeded.\n")


def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(root_dir)

    # 1. Build PyInstaller distribution
    spec_file = os.path.join(root_dir, "azure-tagday-ui.spec")
    if not os.path.exists(spec_file):
        logger.error(f"Spec file not found: {spec_file}")
        sys.exit(1)

    run_command(["pyinstaller", "--noconfirm", spec_file], "Building PyInstaller bundle")

    # 2. Build Windows installer using NSIS or Inno Setup
    nsis_exe = find_nsis()
    inno_exe = find_inno_setup()

    if nsis_exe:
        nsi_file = os.path.join(root_dir, "installer.nsi")
        setup_exe = os.path.join(root_dir, "dist", "AzureTagDayUI-Setup-0.1.0.exe")
        if os.path.exists(setup_exe):
            try:
                os.remove(setup_exe)
            except Exception as e:
                logger.warning(f"Could not remove existing setup exe {setup_exe}: {e}")
        run_command([nsis_exe, nsi_file], "Compiling NSIS Windows Installer")
    elif inno_exe:
        iss_file = os.path.join(root_dir, "installer.iss")
        setup_exe = os.path.join(root_dir, "dist", "AzureTagDayUI-InnoSetup-0.1.0.exe")
        if os.path.exists(setup_exe):
            try:
                os.remove(setup_exe)
            except Exception as e:
                logger.warning(f"Could not remove existing setup exe {setup_exe}: {e}")
        run_command([inno_exe, iss_file], "Compiling Inno Setup Windows Installer")
    else:
        logger.warning("Neither NSIS (makensis) nor Inno Setup (ISCC) found.")
        logger.warning("The PyInstaller distribution in 'dist/azure-tagday-ui/' is ready for manual distribution.")

    # 3. Build Python Wheel package via uv build
    uv_exe = shutil.which("uv")
    if uv_exe:
        run_command([uv_exe, "build"], "Building distributable Python Wheel (.whl) & sdist")

    logger.info("==================================================")
    logger.info("All build artifacts generated in 'dist/' directory:")
    dist_dir = os.path.join(root_dir, "dist")
    if os.path.exists(dist_dir):
        for item in os.listdir(dist_dir):
            p = os.path.join(dist_dir, item)
            size_mb = os.path.getsize(p) / (1024 * 1024) if os.path.isfile(p) else None
            size_str = f" ({size_mb:.1f} MB)" if size_mb is not None else " [directory]"
            logger.info(f" - {item}{size_str}")
    logger.info("==================================================")


if __name__ == "__main__":
    main()
