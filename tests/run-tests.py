#!/usr/bin/env python3
"""
Master Test Runner for n8n EC2 Deploy
Runs all test suites and reports status.
"""

import sys
import unittest
import os

def run_all_tests():
    test_dir = os.path.dirname(os.path.abspath(__file__))
    suite = unittest.defaultTestLoader.discover(test_dir, pattern="test_*.py")
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    if result.wasSuccessful():
        print("\n[✓ SUCCESS] All test suites passed successfully!")
        return 0
    else:
        print(f"\n[✖ FAILED] {len(result.failures)} failures, {len(result.errors)} errors encountered.")
        return 1

if __name__ == "__main__":
    sys.exit(run_all_tests())

