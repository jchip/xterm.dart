import fcntl
import os
import pty
import select
import struct
import sys
import termios

if len(sys.argv) < 4:
    sys.exit(1)

cols = int(sys.argv[1])
rows = int(sys.argv[2])
cmd = sys.argv[3:]

master, slave = pty.openpty()

winsize = struct.pack("HHHH", rows, cols, 0, 0)
fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

pid = os.fork()
if pid == 0:
    os.close(master)
    os.setsid()
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    os.close(slave)
    os.execvp(cmd[0], cmd)
    os._exit(1)

os.close(slave)

fl = fcntl.fcntl(sys.stdin.fileno(), fcntl.F_GETFL)
fcntl.fcntl(sys.stdin.fileno(), fcntl.F_SETFL, fl | os.O_NONBLOCK)

try:
    while True:
        r, _, _ = select.select([master, sys.stdin.fileno()], [], [], 0.05)
        if master in r:
            data = os.read(master, 4096)
            if not data:
                break
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        if sys.stdin.fileno() in r:
            try:
                data = sys.stdin.buffer.read(4096)
                if data:
                    os.write(master, data)
            except (BlockingIOError, IOError):
                pass
except (OSError, KeyboardInterrupt):
    pass
finally:
    try:
        os.kill(pid, 9)
    except Exception:
        pass
    os.close(master)
