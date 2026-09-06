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
    """
    progress = Signal(int, str)      # percent (0-100), message
    log_message = Signal(str)        # single line log
    finished_task = Signal(bool, str) # success, summary message

    def __init__(self, task_func, *args, **kwargs):
        super().__init__()
        self.task_func = task_func
        self.args = args
        self.kwargs = kwargs

    def run(self):
        try:
            self.log_message.emit("Task started...")
            result = self.task_func(self, *self.args, **self.kwargs)
            summary = str(result) if result is not None else "Completed successfully"
            self.log_message.emit(f"Task finished: {summary}")
            self.finished_task.emit(True, summary)
        except Exception as e:
            err_msg = f"Task error: {e}"
            logger.error(err_msg, exc_info=True)
            self.log_message.emit(err_msg)
            self.finished_task.emit(False, str(e))
