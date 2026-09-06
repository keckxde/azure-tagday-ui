# -*- coding: UTF-8 -*-
"""
Main application launcher for the DevOps Manager Qt/QML GUI.
"""
import os
import sys
import argparse
import logging
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QUrl, QTimer

from PySide6.QtQuickControls2 import QQuickStyle

# Configure root directory in sys.path
py_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if py_dir not in sys.path:
    sys.path.insert(0, py_dir)

from gui.backend import DevOpsBackend

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("gui.main")


def main():
    parser = argparse.ArgumentParser(description="DevOps Manager GUI")
    parser.add_argument("--test", action="store_true", help="Run in test mode (load QML, verify bindings, and exit)")
    args = parser.parse_args()

    # Set QQuickStyle to Basic so custom background / styling is fully supported
    QQuickStyle.setStyle("Basic")

    app = QApplication(sys.argv)
    app.setApplicationName("DevOps Manager")
    app.setOrganizationName("keckx")

    engine = QQmlApplicationEngine()

    # Backend instantiation
    backend = DevOpsBackend()
    engine.rootContext().setContextProperty("backend", backend)

    # Load Main.qml
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        qml_candidates = [
            os.path.join(sys._MEIPASS, "gui", "qml", "Main.qml"),
            os.path.join(sys._MEIPASS, "src", "gui", "qml", "Main.qml"),
            os.path.join(sys._MEIPASS, "qml", "Main.qml"),
        ]
        qml_file = next((c for c in qml_candidates if os.path.exists(c)), qml_candidates[0])
    else:
        qml_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qml", "Main.qml")

    logger.info(f"Loading QML from: {qml_file}")
    engine.load(QUrl.fromLocalFile(qml_file))

    if not engine.rootObjects():
        logger.error("Failed to load QML root object!")
        sys.exit(1)

    logger.info("QML interface initialized successfully")

    if args.test:
        logger.info("Test mode active: verifying and exiting cleanly.")
        QTimer.singleShot(1000, app.quit)
    else:
        # Kick off initial cache load in background after the window is fully shown
        QTimer.singleShot(0, backend.startup_load_async)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
