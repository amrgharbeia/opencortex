import pty
import os
import sys
import time
import select
import re

class VirtualTerminal:
    def __init__(self, rows=24, cols=80):
        self.rows = rows
        self.cols = cols
        self.buffer = [[' ' for _ in range(cols)] for _ in range(rows)]
        self.cursor_y = 0
        self.cursor_x = 0
        
    def _strip_ansi(self, text):
        # Very basic ANSI parser for cursor moves and clears
        # CSI n ; m H  (cursor move)
        # CSI J        (clear screen)
        # CSI K        (clear line)
        
        # This is a simplified state machine
        parts = re.split(r'(\x1b\[[0-9;?]*[a-zA-Z])', text)
        for part in parts:
            if part.startswith('\x1b['):
                cmd = part[-1]
                params = part[2:-1].split(';')
                if cmd == 'H' or cmd == 'f': # Move cursor
                    self.cursor_y = int(params[0]) - 1 if params[0] else 0
                    self.cursor_x = int(params[1]) - 1 if (len(params) > 1 and params[1]) else 0
                elif cmd == 'J': # Clear
                    mode = int(params[0]) if params[0] else 0
                    if mode == 2: # Full clear
                        self.buffer = [[' ' for _ in range(self.cols)] for _ in range(self.rows)]
                elif cmd == 'm': # Attributes - ignore for now
                    pass
            else:
                for char in part:
                    if char == '\n':
                        self.cursor_y += 1
                        self.cursor_x = 0
                    elif char == '\r':
                        self.cursor_x = 0
                    elif 0 <= self.cursor_y < self.rows and 0 <= self.cursor_x < self.cols:
                        self.buffer[self.cursor_y][self.cursor_x] = char
                        self.cursor_x += 1

    def get_screen(self):
        return "\n".join(["".join(row) for row in self.buffer])

def run_test(command, input_sequence, wait_time=5):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm"
        os.environ["COLUMNS"] = "80"
        os.environ["LINES"] = "24"
        os.execvp(command[0], command)
    else:
        vt = VirtualTerminal()
        start_time = time.time()
        input_sent = False
        
        while time.time() - start_time < wait_time:
            r, w, e = select.select([fd], [], [], 0.1)
            if fd in r:
                try:
                    data = os.read(fd, 8192).decode(errors='ignore')
                    vt._strip_ansi(data)
                except OSError:
                    break
            
            if not input_sent and time.time() - start_time > 2:
                os.write(fd, input_sequence.encode())
                input_sent = True
        
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        return vt

if __name__ == "__main__":
    # Example usage: python3 ui_driver.py sbcl --eval ...
    vt = run_test(sys.argv[1:], "Hi\r", wait_time=10)
    print("--- VIRTUAL SCREEN SNAPSHOT ---")
    print(vt.get_screen())
    print(f"--- CURSOR POSITION: ({vt.cursor_y}, {vt.cursor_x}) ---")
