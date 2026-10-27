"""Behavioral regressions found in the 2.0 audit. Each test uses isolated real files."""
import sys,os,unittest,tempfile,json,io,zipfile,lzma,bz2
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.environ.get('ORBITA_ENGINE',str(ROOT/'Engine')))
import engine as E
E.RES=ROOT/'Orbita.app/Contents/Resources'
from PIL import Image
import pymupdf as fitz
from docx import Document
class Regressions(unittest.TestCase):
 def setUp(self):self.temp=tempfile.TemporaryDirectory();self.t=Path(self.temp.name);E.OUTPUTS.clear()
 def tearDown(self):self.temp.cleanup()
 def runop(self,action,paths,p={}):
  E.OUTPUTS.clear();return [Path(x) for x in E.execute({'action':action,'paths':list(map(str,paths)),'params':p})]
 def transparent(self):
  path=self.t/'alpha.png';Image.new('RGBA',(40,40),(0,0,0,0)).save(path);return path
 def test_01_grayscale_preserves_alpha(self):
  result=Image.open(self.runop('image.gray',[self.transparent()])[0]);self.assertIn('A',result.getbands());self.assertEqual(result.getpixel((0,0))[-1],0)
 def test_02_all_pdf_pages_have_white_transparent_background(self):
  source=self.transparent();result=self.runop('image.combine',[source,source])[0]
  with fitz.open(result) as pdf:
   for page in pdf:self.assertGreater(min(page.get_pixmap().pixel(0,0)),245)
 def test_03_ods_keeps_zero_and_false(self):
  source=self.t/'values.json';source.write_text('[[0, false, null]]');out=self.runop('sheet.to.ods',[source])[0]
  values=E.read_sheet(out)[0];self.assertEqual(str(values[0]),'0');self.assertEqual(str(values[1]).lower(),'false')
 def test_04_plain_text_is_not_markdown(self):
  source=self.t/'literal.txt';source.write_text('# heading\n**literal**\n<keep>\n')
  out=self.runop('document.to.docx',[source])[0];text='\n'.join(p.text for p in Document(out).paragraphs)
  self.assertIn('# heading',text);self.assertIn('**literal**',text);self.assertIn('<keep>',text)
 def test_05_video_with_odd_dimensions_encodes(self):
  source=self.t/'odd.mov';E.ff(['-f','lavfi','-i','testsrc=size=321x241:rate=5:duration=0.4','-c:v','png',source])
  out=self.runop('video.to.mp4',[source])[0];self.assertGreater(out.stat().st_size,0)
 def test_06_palette_transparency_becomes_white_in_jpeg(self):
  im=Image.new('P',(40,40),0);im.putpalette([0,0,0]+[255,0,0]*255);source=self.t/'alpha.gif';im.save(source,transparency=0)
  out=self.runop('image.to.jpg',[source])[0];self.assertGreater(min(Image.open(out).getpixel((0,0))),245)
 def test_07_archives_preserve_empty_directories(self):
  source=self.t/'folder';(source/'empty').mkdir(parents=True)
  for kind in ['zip','tar','tar.gz']:
   archive=self.runop('archive.'+kind,[source])[0];out=self.runop('archive.extract',[archive])[0];self.assertTrue((out/'folder/empty').is_dir(),kind)
 def test_08_subtitle_shift_does_not_change_dialogue(self):
  source=self.t/'subtitle.srt';source.write_text('1\n00:00:01,000 --> 00:00:03,000\nAt 00:01:00,000 we meet.\n')
  out=self.runop('subtitle.shift',[source],{'seconds':'2'})[0];s=out.read_text();self.assertIn('00:00:03,000 --> 00:00:05,000',s);self.assertIn('At 00:01:00,000 we meet.',s)
 def test_09_single_compressed_streams_extract(self):
  for ext,encoder in [('xz',lzma.compress),('bz2',bz2.compress)]:
   source=self.t/('hello.txt.'+ext);source.write_bytes(encoder(b'Orbita'))
   out=self.runop('archive.extract',[source])[0];self.assertEqual((out/'hello.txt').read_bytes(),b'Orbita')
 def test_10_renaming_symlink_never_renames_target(self):
  target=self.t/'original.txt';target.write_text('important');link=self.t/'link.txt';link.symlink_to(target)
  try:self.runop('files.renameOriginals',[link],{'prefix':'New','start':'1'})
  except E.UserError:pass
  self.assertTrue(target.exists(),'The link target was renamed');self.assertEqual(target.read_text(),'important')
if __name__=='__main__':unittest.main(verbosity=2)
