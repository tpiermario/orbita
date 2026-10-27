import sys,tempfile,json,subprocess,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];RES=ROOT/'Orbita.app/Contents/Resources';sys.path.insert(0,str(RES/'Engine'))
import engine as E
from PIL import Image
import py7zr
passed=[]
with tempfile.TemporaryDirectory(prefix='orbita-edges-') as tmp:
 t=Path(tmp);im=t/'source.png';Image.new('RGB',(321,241),'orange').save(im)
 def execute(id,paths,params={}):
  E.OUTPUTS.clear();out=list(E.execute({'action':id,'paths':list(map(str,paths)),'params':params}));assert out;passed.append(id);print('PASS',id,flush=True);return [Path(x) for x in out]
 # Fixed regressions + new operation.
 execute('vision.qr',[im]);execute('files.strip',[im])
 pdf=execute('image.to.pdf',[im])[0];execute('pdf.to.epub',[pdf])
 csv=t/'data.csv';csv.write_text('A,B\n1,2\n');execute('sheet.to.ods',[csv])
 encrypted=execute('archive.password',[im,csv],{'password':'test-only-password'})[0]
 extracted=execute('archive.extract',[encrypted],{'password':'test-only-password'})[0]
 assert (extracted/im.name).read_bytes()==im.read_bytes()
 seven=t/'test.7z'
 with py7zr.SevenZipFile(seven,'w',password='test') as z:z.write(im,'source.png')
 target=execute('archive.extract',[seven],{'password':'test'})[0];assert (target/'source.png').exists()
 # RAR fixture from the upstream libarchive test suite is optional.
 video=t/'silent.mp4';E.ff(['-f','lavfi','-i','color=c=blue:s=320x240:r=15:d=2']+E.vcodec('mp4')+[video])
 audio=t/'sound.wav';E.ff(['-f','lavfi','-i','sine=frequency=440:duration=2',audio])
 voiced=t/'voiced.mp4';E.ff(['-i',video,'-i',audio,'-c:v','copy','-c:a','aac','-shortest',voiced])
 out=execute('video.join',[video,voiced])[0];assert 3.8<E.duration(out)<4.5
 stripped=execute('video.strip',[voiced])[0];assert stripped.suffix=='.mp4'
 stripped=execute('audio.strip',[audio])[0];assert stripped.suffix=='.wav'
 execute('video.crop',[voiced],{'x':'0','y':'0','width':'101','height':'101'})
 srt=t/'sub.srt';srt.write_text('1\n00:00:00,000 --> 00:00:01,000\nOrbita text\n')
 subbed=execute('video.addsubs',[voiced],{'file':str(srt)})[0]
 extracted=execute('video.extractsubs',[subbed])[0];assert 'Orbita text' in extracted.read_text()
 # Destination remapping must survive /var -> /private/var resolution.
 newdir=t/'destination';newdir.mkdir();fake=newdir/'source.pages'
 E.OUTPUTS.clear();E.execute({'action':'image.to.jpg','paths':[str(im)],'params':{},'destinations':{str(im):str(fake)}})
 assert Path(E.OUTPUTS[0]).parent==newdir;passed.append('destination-remapping')
 # Production runner, not a direct import.
 req=t/'request.json';req.write_text(json.dumps({'action':'image.resize','paths':[str(im)],'params':{'width':'100','height':'0'}}))
 response=subprocess.run([sys.executable,'-I',str(RES/'Engine/runner.py'),str(req)],capture_output=True,text=True,check=True)
 data=json.loads(response.stdout);assert data['ok'];assert Image.open(data['outputs'][0]).width==100;passed.append('isolated-runner')
 # Portable Whisper build and a known synthesized sentence.
 speech=t/'voice.aiff';subprocess.run(['/usr/bin/say','-v','Samantha','-o',str(speech),'Hello, this is a test of the local audio transcription system.'],check=True)
 for ext in ['txt','srt','vtt']:
  out=execute('transcribe.'+ext,[speech])[0];assert 'transcription' in out.read_text().lower()
 # Automatic subtitle burn: synthesize a video with the same speech.
 spoken=t/'spoken.mp4';E.ff(['-f','lavfi','-i','color=c=blue:s=320x240:r=15','-i',speech,'-shortest']+E.vcodec('mp4')+[spoken])
 execute('video.autosubs',[spoken])
 Path(sys.argv[1]).write_text(json.dumps({'passed':passed,'failed':[]},indent=2))
 print('PASS all',len(passed))
