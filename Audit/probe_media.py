exec(open(__import__('pathlib').Path(__file__).with_name('probe_engine.py')).read().split('png=pic()')[0])
video=D/'video.mp4';E.ff(['-f','lavfi','-i','color=c=red:s=64x48:r=10:d=1','-f','lavfi','-i','sine=frequency=440:duration=1','-c:v','libx264','-c:a','aac','-shortest',video])
audio=D/'audio.wav';E.ff(['-f','lavfi','-i','sine=frequency=440:duration=1',audio])
def info(p):return E.subprocess.run([E.ffmpeg(),'-hide_banner','-i',str(p)],capture_output=True).stderr.decode()
def trim():
 q=op('audio.trim',[audio],{'start':5,'end':6})[0];return {'bytes':q.stat().st_size,'info':info(q)}
probe('Trim beyond duration reports success with empty media',trim)
def subs():
 s=D/'old.srt';s.write_text('1\n00:00:00,000 --> 00:00:00,800\nOLD\n');p=D/'withsubs.mp4';E.ff(['-i',video,'-i',s,'-map','0','-map','1','-c','copy','-c:s','mov_text',p]);n=D/'new.srt';n.write_text('1\n00:00:00,000 --> 00:00:00,800\nNEW\n');q=op('video.addsubs',[p],{'file':str(n)})[0];return {'before_subtitle_tracks':info(p).count('Subtitle:'),'after_subtitle_tracks':info(q).count('Subtitle:')}
probe('Add subtitles drops existing subtitle tracks',subs)
def streammeta():
 p=D/'private.mkv';E.ff(['-i',video,'-c','copy','-metadata:s:v:0','title=PRIVATE_AUDIT',p]);q=op('video.strip',[p])[0];return {'private_before':'PRIVATE_AUDIT' in info(p),'private_after':'PRIVATE_AUDIT' in info(q)}
probe('Video metadata stripping leaves stream metadata',streammeta)
def tags():
 cover=pic('cover.jpg',color='red') if False else D/'cover.jpg';Image.new('RGB',(32,32),'red').save(cover);p=D/'album.mp3';E.ff(['-i',audio,'-i',cover,'-map','0:a','-map','1:v','-c:a','libmp3lame','-c:v','mjpeg','-id3v2_version','3','-disposition:v','attached_pic',p]);q=op('audio.tags',[p],{'title':'New'})[0];return {'cover_before':'attached pic' in info(p),'cover_after':'attached pic' in info(q),'output_extension':q.suffix}
probe('Editing audio tags removes artwork and transcodes',tags)
def sampledepth():
 p=D/'hires.wav';E.ff(['-i',audio,'-c:a','pcm_s24le',p]);q=op('audio.to.flac',[p])[0];r=op('audio.to.wav',[q])[0];return {'input':info(p),'output':info(r)}
probe('Lossless WAV conversion reduces 24 bit to16 without option',sampledepth)
def cropclamp():
 q=op('video.crop',[video],{'x':1000,'y':1000,'width':20,'height':20})[0];return {'accepted_outside_bounds':q.exists()}
probe('Video crop silently clamps outside coordinates',cropclamp)
(ROOT/'Audit/media-probes.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print('FIXTURES',D)
