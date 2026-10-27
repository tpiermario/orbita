import unittest,sys
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Engine'))
import engine as E
class ArchitectureRouting(unittest.TestCase):
 def test_office_native_for_each_processor(self):
  for arch,directory in [('x86_64','Office'),('arm64','Office-arm64')]:
   with patch.object(E.platform,'machine',return_value=arch),patch.object(Path,'exists',return_value=True):
    self.assertEqual(E.libreoffice(),E.RES/directory/'LibreOffice.app/Contents/MacOS/soffice')
 def test_transcription_native_for_each_processor(self):
  import tempfile
  for arch,directory in [('x86_64','bin'),('arm64','bin/arm64')]:
   with tempfile.TemporaryDirectory() as tmp,patch.object(E.platform,'machine',return_value=arch),patch.object(Path,'exists',return_value=True),patch.object(E,'ff'),patch.object(E,'run') as run:
    E.transcription('input.wav','txt',tmp);self.assertEqual(run.call_args[0][0][0],E.RES/directory/'whisper-cli')
if __name__=='__main__':unittest.main(verbosity=2)
