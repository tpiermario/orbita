# Isolated interpreter: only bundled modules and the engine are loaded.
import sys
sys.dont_write_bytecode=True
import pathlib,runpy,signal,os
# Keep protocol output separate from Python and native-library diagnostics.
response_fd=os.dup(1)
os.dup2(2,1)
sys.path.insert(0,str(pathlib.Path(__file__).parent))
def stop(signum,frame):
 import psutil
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 children=psutil.Process().children(recursive=True)
 for child in children:
  try:child.terminate()
  except psutil.Error:pass
 _,alive=psutil.wait_procs(children,timeout=2)
 for child in alive:
  try:child.kill()
  except psutil.Error:pass
 raise SystemExit(130)
signal.signal(signal.SIGTERM,stop)
runpy.run_path(str(pathlib.Path(__file__).with_name('engine.py')),run_name='__main__',init_globals={'RESPONSE_FD':response_fd})
