"""The same subprocess protocol used by the native app must remain valid JSON."""
import unittest,sys,subprocess,tempfile,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class Protocol(unittest.TestCase):
 def test_pdf_native_diagnostics_do_not_corrupt_response(self):
  with tempfile.TemporaryDirectory() as tmp:
   t=Path(tmp);doc=t/'input.txt';doc.write_text('Ciao 中文 €',encoding='utf-16');req=t/'request.json';req.write_text(json.dumps({'action':'document.to.pdf','paths':[str(doc)]}))
   p=subprocess.run([sys.executable,'-I',str(ROOT/'Engine/runner.py'),str(req)],capture_output=True,text=True,check=True)
   response=json.loads(p.stdout);self.assertTrue(response['ok']);self.assertTrue(Path(response['outputs'][0]).is_file())
 def test_runner_does_not_modify_writable_bundle(self):
  import shutil
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);engine=root/'Engine';engine.mkdir()
   shutil.copy2(ROOT/'Engine/runner.py',engine/'runner.py')
   (engine/'cache_probe.py').write_text('value=42')
   (engine/'engine.py').write_text('import cache_probe,os,json\nos.write(RESPONSE_FD,json.dumps({"ok":cache_probe.value==42}).encode())')
   result=subprocess.run([sys.executable,'-I',str(engine/'runner.py')],capture_output=True,text=True,check=True)
   self.assertTrue(json.loads(result.stdout)['ok'])
   self.assertFalse(list(root.rglob('*.pyc')))
   self.assertFalse(list(root.rglob('__pycache__')))
 def test_error_is_valid_json_with_nonzero_status(self):
  with tempfile.TemporaryDirectory() as tmp:
   req=Path(tmp)/'req.json';req.write_text(json.dumps({'action':'not-an-action','paths':[]}))
   p=subprocess.run([sys.executable,'-I',str(ROOT/'Engine/runner.py'),str(req)],capture_output=True,text=True)
   self.assertNotEqual(p.returncode,0);r=json.loads(p.stdout);self.assertFalse(r['ok']);self.assertTrue(r['error'])
if __name__=='__main__':unittest.main(verbosity=2)
