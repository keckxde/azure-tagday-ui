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

    sys.path.insert(0, os.path.join(root_dir, "src"))
    try:
        from version import get_version_info
        v_info = get_version_info()
        raw_tag = v_info.get("tag") or "v0.1.0"
        app_version = raw_tag.lstrip("v")
    except Exception as e:
        logger.warning(f"Could not load dynamic version: {e}")
        app_version = "0.1.0"

    logger.info(f"Target build version: {app_version}")

    # Clean old build artifacts from dist/
    dist_dir = os.path.join(root_dir, "dist")
    if os.path.exists(dist_dir):
        logger.info("Cleaning previous build artifacts from dist/...")
        for item in os.listdir(dist_dir):
            if item == ".gitignore":
                continue
            item_path = os.path.join(dist_dir, item)
            try:
                if os.path.isfile(item_path):
                    os.remove(item_path)
                elif os.path.isdir(item_path):
                    shutil.rmtree(item_path)
            except Exception as e:
                logger.warning(f"Could not remove old artifact {item}: {e}")

    # 1. Build PyInstaller distribution
    spec_file = os.path.join(root_dir, "azure-tagday-ui.spec")
    if not os.path.exists(spec_file):
        logger.error(f"Spec file not found: {spec_file}")
        sys.exit(1)

    run_command(["pyinstaller", "--noconfirm", spec_file], "Building PyInstaller bundle")

    # Create portable zip archive of PyInstaller standalone bundle
    bundle_dir = os.path.join(root_dir, "dist", "azure-tagday-ui")
    if os.path.exists(bundle_dir):
        zip_base = os.path.join(root_dir, "dist", f"azure-tagday-ui-windows-x64-{app_version}")
        logger.info(f"Creating portable zip archive: {zip_base}.zip...")
        shutil.make_archive(zip_base, "zip", root_dir=os.path.join(root_dir, "dist"), base_dir="azure-tagday-ui")
        # Also create a generic named zip for CI releases
        shutil.copyfile(f"{zip_base}.zip", os.path.join(root_dir, "dist", "azure-tagday-ui-windows-x64.zip"))

    # 2. Build Windows installer using NSIS or Inno Setup
    nsis_exe = find_nsis()
    inno_exe = find_inno_setup()

    if nsis_exe:
        nsi_file = os.path.join(root_dir, "installer.nsi")
        run_command([nsis_exe, f"-DPRODUCT_VERSION={app_version}", nsi_file], f"Compiling NSIS Windows Installer (v{app_version})")
    elif inno_exe:
        iss_file = os.path.join(root_dir, "installer.iss")
        run_command([inno_exe, f"/DPRODUCT_VERSION={app_version}", iss_file], f"Compiling Inno Setup Windows Installer (v{app_version})")
    else:
        logger.warning("Neither NSIS (makensis) nor Inno Setup (ISCC) found.")
        logger.warning("The PyInstaller distribution in 'dist/azure-tagday-ui/' and portable zip are ready.")

    # 3. Build Python Wheel package via uv build or python -m build
    uv_exe = shutil.which("uv")
    if uv_exe:
        run_command([uv_exe, "build"], "Building distributable Python Wheel (.whl) & sdist")
    else:
        try:
            import build  # type: ignore
            run_command([sys.executable, "-m", "build"], "Building Python Wheel (.whl) & sdist via build module")
        except ImportError:
            logger.warning("Neither uv nor python-build module found; skipping wheel package generation.")

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
