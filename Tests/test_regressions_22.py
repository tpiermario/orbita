"""Thirty correctness regressions, B21–B50. Reuse the preserved audit fixtures."""
import unittest,sys,tempfile,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def fixtures(name):
 path=ROOT/'Audit'/name
 code=path.read_text()
 code='\n'.join(line for line in code.splitlines() if not line.startswith('probe('))
 if name=='probe_engine.py':code=code.split("(D/'results.json')")[0]
 else:code=code.split("(ROOT/'Audit/media-probes.json')")[0]
 ns={'__file__':str(path),'__name__':'audit_fixture'};exec(compile(code,str(path),'exec'),ns);return ns
A=fixtures('probe_engine.py');M=fixtures('probe_media.py');E=A['E']
class FixedAudit(unittest.TestCase):
 @classmethod
 def tearDownClass(cls):
  for ns in [A,M]:shutil.rmtree(ns['D'])
 def test_B21_gif_once(self):self.assertIsNone(A['gifloop']()['output_loop'])
 def test_B22_exact_redaction(self):self.assertEqual(A['redact']()['black_pixels'],1)
 def test_B23_panorama_compression(self):self.assertEqual(A['compress'](),'success')
 def test_B24_color_profile(self):self.assertTrue(A['icc']()['output_has_profile'])
 def test_B25_original_alpha(self):self.assertEqual(A['alpha_mask']()['output_alpha'],0)
 def test_B26_original_metadata(self):
  r=A['meta']();self.assertEqual(r['size'],[40,20]);self.assertEqual(r['exif']['274'],6)
 def test_B27_unicode_pdf(self):self.assertIn('Ελληνικά 中文 €',A['unicodepdf']())
 def test_B28_pdf_image_alpha(self):self.assertIn('A',A['extractalpha']()['mode'])
 def test_B29_slides_aspect(self):
  r=A['pptaspect']();self.assertAlmostEqual(r['original_aspect'],r['output_aspect'],places=4)
 def test_B30_ocr_no_duplicates(self):self.assertEqual(A['ocrduplicate']().count('Hello World'),1)
 def test_B31_offpage_rejected(self):
  with self.assertRaisesRegex(E.UserError,'pagina'):A['pdfbounds']()
 def test_B32_merge_bookmarks(self):self.assertEqual(A['outline']()['output_toc'],[[1,'Chapter',1],[1,'Chapter',2]])
 def test_B33_first_sheet(self):self.assertEqual(A['active_sheet']().strip(),'FIRST')
 def test_B34_formula_recalculation(self):self.assertEqual(A['formulas']()[0][2],3)
 def test_B35_literal_cell(self):self.assertEqual(A['apostrophe']().strip(),'-10,+391234,=literal,@name')
 def test_B36_ods_numeric(self):self.assertEqual(A['odsvalue'](),[[42]])
 def test_B37_ods_repetitions(self):self.assertEqual(A['odsrepeat']()['actual'],10001)
 def test_B38_ods_covered_cells(self):self.assertEqual(A['odscovered'](),[['A','','C']])
 def test_B39_no_silent_truncation(self):
  with self.assertRaisesRegex(E.UserError,'32767'):A['longcell']()
 def test_B40_utf16(self):self.assertEqual(A['txt16'](),'success')
 def test_B41_relative_images(self):self.assertGreater(A['resource']()['embedded_images'],0)
 def test_B42_html_embedded_image(self):
  r=A['standalonehtml']();self.assertTrue(r['src']);self.assertTrue(all(x.startswith('data:') for x in r['src']))
 def test_B43_no_trailing_dot(self):self.assertEqual(A['renamedot'](),'Copy-0001')
 def test_B44_idempotent_rename(self):self.assertEqual(A['renameidempotent'](),'File-0001.txt')
 def test_B45_custom_metadata(self):
  import zipfile
  try:r=A['stripcustom']();self.assertFalse(r['private_metadata_remains'])
  except KeyError: # Correct: custom part removed, and the package must remain readable.
   from docx import Document
   p=sorted(A['D'].glob('custom-orbita*.docx'))[-1];Document(p)
   with zipfile.ZipFile(p) as z:
    self.assertNotIn('docProps/custom.xml',z.namelist());self.assertNotIn(b'custom-properties',z.read('_rels/.rels'))
 def test_B46_trim_bounds(self):
  with self.assertRaisesRegex(E.UserError,'durata'):M['trim']()
 def test_B47_keep_subtitles(self):self.assertEqual(M['subs']()['after_subtitle_tracks'],2)
 def test_B48_keep_audio_artwork(self):
  r=M['tags']();self.assertTrue(r['cover_after']);self.assertEqual(r['output_extension'],'.mp3')
 def test_B49_audio_bitdepth(self):self.assertIn('pcm_s24le',M['sampledepth']()['output'])
 def test_B50_crop_bounds(self):
  with self.assertRaisesRegex(E.UserError,'bordi'):M['cropclamp']()
if __name__=='__main__':unittest.main(verbosity=2)
