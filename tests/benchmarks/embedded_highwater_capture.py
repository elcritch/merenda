import os,subprocess,time,sys,pathlib
variant,stage,tag=sys.argv[1:]
base=f'/tmp/merenda-embedded-highwater-{tag}'
env=dict(os.environ,MERENDA_EMBED_PAUSE=stage,MallocStackLogging='all')
with open(base+'.out','w') as output, open(base+'.err','w') as error:
 p=subprocess.Popen([f'/tmp/merenda-embedded-trace-{variant}','12'],stdin=subprocess.PIPE,stdout=output,stderr=error,env=env)
 try:
  end=time.monotonic()+120
  while time.monotonic()<end:
   if p.poll() is not None: raise Exception(f'process exited {p.returncode}')
   if '"stage":"'+stage+'"' in pathlib.Path(base+'.out').read_text(): break
   time.sleep(.01)
  else: raise Exception('checkpoint timeout')
  with open(base+'.tree','w') as v:
   proc=subprocess.run(['malloc_history',str(p.pid),'-highWaterMark','-callTree','-invert','-noContent'],stdout=v,stderr=subprocess.STDOUT,timeout=180)
  if proc.returncode: raise Exception(f'malloc_history exited {proc.returncode}')
  p.stdin.write(b'\n');p.stdin.flush()
  if p.wait(timeout=120): raise Exception(f'process exit {p.returncode}')
  print(variant,stage,tag,'ok')
 finally:
  if p.poll() is None: p.kill();p.wait()
