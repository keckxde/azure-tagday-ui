#!/usr/bin/env python3
# -*- coding: UTF-8 -*-
"""
Test runner for Azure DevOps Python modules.

Usage:
    python -m unittest discover -s tests
    python tests/run_tests.py
"""
import os
import sys
import unittest

def main():
    # Set base directory
    test_dir = os.path.dirname(os.path.abspath(__file__))
    py_dir = os.path.dirname(test_dir)
    root_dir = os.path.dirname(py_dir)
    for p in (root_dir, py_dir):
        if p not in sys.path:
            sys.path.insert(0, p)

    print(f"============================================================")
    print(f"Running Azure DevOps Python Unit Tests")
    print(f"Test directory: {test_dir}")
    print(f"============================================================")

    loader = unittest.TestLoader()
    suite = loader.discover(start_dir=test_dir, pattern="test_*.py", top_level_dir=py_dir)

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 60)
    print(f"Tests run: {result.testsRun}")
    print(f"Errors: {len(result.errors)}")
    print(f"Failures: {len(result.failures)}")
    print(f"Skipped: {len(result.skipped)}")
    print("=" * 60)

    if not result.wasSuccessful():
        sys.exit(1)
    print("ALL TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
