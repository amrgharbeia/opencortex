import sys
import os
import time

# Add scripts directory to path to import ui_driver
sys.path.append(os.path.join(os.getcwd(), 'scripts'))
from ui_driver import run_test


def wait_for_brain():
    print("[UI TEST] Waiting for Brain to wake up...")
    for i in range(60):
        if os.path.exists('brain.log'):
            with open('brain.log', 'r') as f:
                if 'Boot Complete' in f.read():
                    print("[UI TEST] Brain is Green. Waiting for TCP listener...")
                    time.sleep(5)
                    return True
        time.sleep(2)
    return False

def test_tui_boot_and_input():
    if not wait_for_brain():
        print("FAIL: Brain failed to boot within timeout.")
        return

    print("[UI TEST] Launching TUI and sending 'Hi'...")
    
    # We run the TUI script via bash
    
    # Direct SBCL launch to bypass shell script noise
    command = ["sbcl", "--disable-debugger", 
               "--eval", "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))",
               "--eval", "(push (truename \"\") asdf:*central-registry*)",
               "--eval", "(ql:quickload :opencortex/tui)",
               "--eval", "(opencortex.tui:main)"]

    vt = run_test(command, "Hi\r", wait_time=15)
    
    screen = vt.get_screen()
    
    # 1. Verify Prompt
    if "> Hi" in screen:
        print("PASS: Local Echo found in chat history.")
    elif ">" in screen:
        print("PASS: Input prompt found.")
    else:
        print("FAIL: No input prompt found.")
        
    # 2. Verify Status Bar
    if "[Scribe:" in screen and "Gardener:" in screen:
        print("PASS: Status bar rendered correctly.")
    else:
        print("FAIL: Status bar missing.")
        
    # 3. Verify Cursor Position (should be at the end of the empty prompt after Enter)
    # The prompt is line 23 (h-1), col 2 (after "> ")
    if vt.cursor_y == 23 and vt.cursor_x == 2:
        print(f"PASS: Cursor is correctly pinned to prompt at ({vt.cursor_y}, {vt.cursor_x}).")
    else:
        print(f"WARN: Cursor at unexpected position ({vt.cursor_y}, {vt.cursor_x}).")

    print("\n--- FINAL SCREEN SNAPSHOT ---")
    print(screen)

if __name__ == "__main__":
    test_tui_boot_and_input()
