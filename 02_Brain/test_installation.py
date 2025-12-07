"""
FlashEASuite V2 - Installation Verification Test
=================================================
Tests that all modules are installed correctly and can be imported.
"""

import sys
import os

def test_python_imports():
    """Test Python module imports"""
    print("=" * 70)
    print("TESTING PYTHON MODULE IMPORTS")
    print("=" * 70)
    
    tests_passed = 0
    tests_failed = 0
    
    # Test 1: Import strategy package
    try:
        from core.strategy import create_strategy_engine_threaded
        print("✅ Test 1: core.strategy import - PASSED")
        tests_passed += 1
    except ImportError as e:
        print(f"❌ Test 1: core.strategy import - FAILED: {e}")
        tests_failed += 1
    
    # Test 2: Import individual modules
    try:
        from core.strategy import engine
        print("✅ Test 2: core.strategy.engine import - PASSED")
        tests_passed += 1
    except ImportError as e:
        print(f"❌ Test 2: core.strategy.engine import - FAILED: {e}")
        tests_failed += 1
    
    # Test 3: Import analysis module
    try:
        from core.strategy import analysis
        print("✅ Test 3: core.strategy.analysis import - PASSED")
        tests_passed += 1
    except ImportError as e:
        print(f"❌ Test 3: core.strategy.analysis import - FAILED: {e}")
        tests_failed += 1
    
    # Test 4: Import feedback module
    try:
        from core.strategy import feedback
        print("✅ Test 4: core.strategy.feedback import - PASSED")
        tests_passed += 1
    except ImportError as e:
        print(f"❌ Test 4: core.strategy.feedback import - FAILED: {e}")
        tests_failed += 1
    
    # Test 5: Import policy module
    try:
        from core.strategy import policy
        print("✅ Test 5: core.strategy.policy import - PASSED")
        tests_passed += 1
    except ImportError as e:
        print(f"❌ Test 5: core.strategy.policy import - FAILED: {e}")
        tests_failed += 1
    
    # Test 6: Check that old strategy.py doesn't interfere
    try:
        import core
        strategy_files = [f for f in os.listdir('core') if 'strategy' in f and f.endswith('.py')]
        if 'strategy.py' in strategy_files:
            print("⚠️  Warning: Old strategy.py still exists in core/")
            print("   (Should be renamed to strategy_old.py or strategy_old_backup.py)")
        else:
            print("✅ Test 6: No old strategy.py conflict - PASSED")
            tests_passed += 1
    except Exception as e:
        print(f"⚠️  Test 6: Could not check for old files: {e}")
    
    # Summary
    print("\n" + "=" * 70)
    print("PYTHON IMPORT TEST SUMMARY")
    print("=" * 70)
    print(f"Tests Passed: {tests_passed}")
    print(f"Tests Failed: {tests_failed}")
    
    if tests_failed == 0:
        print("\n🎉 ALL PYTHON TESTS PASSED! ✅")
        print("Python modules are installed correctly.")
        return True
    else:
        print("\n❌ SOME TESTS FAILED!")
        print("Please check the installation.")
        return False

def test_file_structure():
    """Test that all expected files exist"""
    print("\n" + "=" * 70)
    print("TESTING FILE STRUCTURE")
    print("=" * 70)
    
    expected_files = {
        'Python Strategy Modules': [
            'core/strategy/__init__.py',
            'core/strategy/engine.py',
            'core/strategy/analysis.py',
            'core/strategy/feedback.py',
            'core/strategy/policy.py',
        ],
        'Core Modules': [
            'core/__init__.py',
            'core/execution_listener.py',
            'core/ingestion.py',
        ],
        'Main Files': [
            'main.py',
            'config.py',
        ]
    }
    
    all_exist = True
    
    for category, files in expected_files.items():
        print(f"\n{category}:")
        for file_path in files:
            if os.path.exists(file_path):
                print(f"  ✅ {file_path}")
            else:
                print(f"  ❌ {file_path} - NOT FOUND")
                all_exist = False
    
    if all_exist:
        print("\n✅ All expected files exist!")
        return True
    else:
        print("\n❌ Some files are missing!")
        return False

def main():
    """Run all tests"""
    print("\n")
    print("╔" + "=" * 68 + "╗")
    print("║" + " " * 15 + "FlashEASuite V2 - Installation Test" + " " * 18 + "║")
    print("╚" + "=" * 68 + "╝")
    print()
    
    # Test file structure first
    structure_ok = test_file_structure()
    
    # Test Python imports
    imports_ok = test_python_imports()
    
    # Final summary
    print("\n" + "=" * 70)
    print("FINAL VERIFICATION RESULT")
    print("=" * 70)
    
    if structure_ok and imports_ok:
        print("✅ INSTALLATION VERIFIED SUCCESSFULLY!")
        print("\nYour FlashEASuite V2 installation is complete and working.")
        print("\nNext steps:")
        print("  1. Start the system: python main.py")
        print("  2. Attach FeederEA to MT5")
        print("  3. Attach ProgramC_Trader to MT5")
        return 0
    else:
        print("❌ INSTALLATION HAS ISSUES!")
        print("\nPlease:")
        if not structure_ok:
            print("  - Check that all files are in the correct locations")
        if not imports_ok:
            print("  - Verify Python module installation")
            print("  - Run: pip install -r requirements.txt")
        return 1

if __name__ == "__main__":
    sys.exit(main())
