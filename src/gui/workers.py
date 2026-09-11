# -*- coding: UTF-8 -*-
"""
Background QThread workers for executing long-running DevOps tasks without blocking the QML UI.
"""
import sys
import logging
from PySide6.QtCore import QThread, Signal

logger = logging.getLogger(__name__)


class TaskWorker(QThread):
    """
    Executes a callable in a background thread and emits signals on progress, logs, and completion.
    Supports cancellation tokens for graceful aborting of long-running operations.
    """
    progress = Signal(int, str)       # percent (0-100), message
    log_message = Signal(str)         # single line log
    finished_task = Signal(bool, object) # success, summary message or result object

    def __init__(self, task_func, *args, **kwargs):
        super().__init__()
        self.task_func = task_func
        self.args = args
        self.kwargs = kwargs
        self._is_cancelled = False

    def cancel(self):
        """Marks the worker as cancelled."""
        self._is_cancelled = True
        self.log_message.emit("⏹️ Abort requested by user. Terminating background task...")

    def is_cancelled(self):
        """Returns True if user has requested task cancellation."""
        return self._is_cancelled

    def report_progress(self, percent: int, message: str = ""):
        """Helper to emit progress signals."""
        if not self._is_cancelled:
            self.progress.emit(max(0, min(100, int(percent))), message)

    def run(self):
        try:
            self.log_message.emit("Task started...")
            result = self.task_func(self, *self.args, **self.kwargs)
            if self._is_cancelled:
                self.log_message.emit("Task was aborted.")
                self.finished_task.emit(False, "Task aborted by user")
            else:
                summary = result if result is not None else "Completed successfully"
                log_summary = summary if isinstance(summary, str) else "Completed successfully"
                self.log_message.emit(f"Task finished: {log_summary}")
                self.finished_task.emit(True, summary)
        except Exception as e:
            if self._is_cancelled:
                self.log_message.emit("Task was aborted.")
                self.finished_task.emit(False, "Task aborted by user")
            else:
                err_msg = f"Task error: {e}"
                logger.error(err_msg, exc_info=True)
                self.log_message.emit(err_msg)
                self.finished_task.emit(False, str(e))
