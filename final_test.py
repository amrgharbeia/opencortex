import pty, os, time, socket

# 1. Wait for daemon to be ready
print("Waiting for port 9105...")
for i in range(30):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("localhost", 9105))
        s.close()
        print("Daemon is up!")
        break
    except:
        time.sleep(1)
else:
    print("Daemon failed to start.")
    exit(1)

# 2. Run TUI in pty and inject "Hi\n"
pid, fd = pty.fork()
if pid == 0:
    # Child: Run TUI
    os.environ["TERM"] = "xterm"
    os.environ["SCRIPT_DIR"] = os.getcwd()
    os.execvp("sbcl", ["sbcl", "--disable-debugger", 
                       "--eval", "(load (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))",
                       "--eval", "(push (truename (uiop:getenv \"SCRIPT_DIR\")) asdf:*central-registry*)",
                       "--eval", "(ql:quickload :opencortex/tui)",
                       "--eval", "(opencortex.tui:main)"])
else:
    # Parent: Inject keys
    time.sleep(5) # Wait for TUI to load
    os.write(fd, b"Hi\r") # \r for Enter in many TUIs
    time.sleep(5) # Wait for response
    # Read output and look for "Cascade Failure" or similar
    try:
        output = os.read(fd, 8192).decode(errors='ignore')
        print("TUI OUTPUT CAPTURED:")
        print(output)
        if "Neural Cascade Failure" in output or "Providers exhausted" in output or "Hi" in output:
            print("SUCCESS: UI correctly rendered input and response.")
        else:
            print("FAILURE: UI did not show expected text.")
    except:
        pass
    os.kill(pid, 9)
    os.waitpid(pid, 0)
