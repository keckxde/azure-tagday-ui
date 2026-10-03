# -*- coding: UTF-8 -*-
"""
Logging service & Qt log handler bridge for GUI sync log.
"""
import logging
from datetime import datetime
from PySide6.QtCore import QObject, Signal


class QtLogEmitter(QObject):
    """Bridge for cross-thread signal emission of logging records to Qt main thread."""
    recordReady = Signal(str, str, str, str)  # timestamp, level, logger_name, message


class QtLogHandler(logging.Handler):
    """
    Custom logging handler that intercepts all Python logger messages
    (INFO, WARNING, ERROR, CRITICAL) and forwards them safely to the Qt event loop.
    """
    def __init__(self, emitter):
        super().__init__()
        self.emitter = emitter
        self._in_emit = False

    def emit(self, record):
        if self._in_emit:
            return
        if record.name.startswith("gui.qt_log"):
            return
        try:
            from PySide6.QtCore import QCoreApplication
            if not QCoreApplication.instance():
                return
            from shiboken6 import isValid
            if self.emitter is None or not isValid(self.emitter):
                return
        except Exception:
            return
        try:
            self._in_emit = True
            msg = self.format(record)
            ts = datetime.now().strftime("%H:%M:%S")
            lvl = record.levelname.upper()
            if lvl in ("WARN", "WARNING"):
                lvl = "WARNING"
            elif lvl in ("ERROR", "CRITICAL"):
                lvl = "ERROR"
            else:
                lvl = "INFO"
            if self.emitter is not None:
                self.emitter.recordReady.emit(ts, lvl, record.name, msg)
        except Exception:
            pass
        finally:
            self._in_emit = False


class ConsoleOutputTee:
    """
    Captures console stdout prints and feeds them to the GUI Sync Log as INFO records,
    while preserving standard console printing in the terminal.
    """
    def __init__(self, original_stream, callback):
        self.original_stream = original_stream
        self.callback = callback
        self._buffer = ""

    def write(self, text):
        if self.original_stream:
            try:
                self.original_stream.write(text)
            except Exception:
                pass
        self._buffer += text
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip("\r\n")
            if line:
                try:
                    self.callback(line)
                except Exception:
                    pass

    def flush(self):
        if self.original_stream:
            try:
                self.original_stream.flush()
            except Exception:
                pass
        if self._buffer.strip():
            try:
                self.callback(self._buffer.strip())
            except Exception:
                pass
            self._buffer = ""
