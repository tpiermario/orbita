"""Build redistributable FFmpeg and exactly the codecs used by Orbita, for macOS 12+."""
from pathlib import Path
import subprocess,os,tarfile,shutil,json
root=Path(__file__).resolve().parent; sources=root/'sources'; build=root/'build'; build.mkdir(exist_ok=True)
cmake=Path(os.environ.get('CMAKE', shutil.which('cmake') or 'cmake'))
def extract(archive,name):
 p=build/name
 if not p.exists():
  assert (sources/archive).is_file(), 'Missing source archive: '+archive
  p.mkdir();subprocess.run(['tar','xf',str(sources/archive),'--strip-components=1','-C',str(p)],check=True)
 return p
baseenv=os.environ.copy();baseenv['LDFLAGS']=baseenv.get('LDFLAGS','')+' -Wl,-adhoc_codesign';tools=build/'tools';baseenv['PATH']=str(tools/'bin')+':'+baseenv['PATH']
def run(cmd,cwd,env):
 print('RUN',cwd.name,' '.join(map(str,cmd)),flush=True);subprocess.run(list(map(str,cmd)),cwd=cwd,env=env,check=True)
def make(p,env):run(['make','-j2'],p,env);run(['make','install'],p,env)
# pkgconf is only a build tool.
if not (tools/'bin/pkgconf').exists():
 p=extract('pkgconf-2.3.0.tar.gz','pkgconf');run(['./configure','--prefix='+str(tools),'--disable-shared'],p,baseenv);make(p,baseenv)
if not (tools/'bin/pkg-config').exists():(tools/'bin/pkg-config').symlink_to('pkgconf')
if not (tools/'bin/nasm').exists():
 p=extract('nasm-2.16.03.tar.xz','nasm');run(['./configure','--prefix='+str(tools)],p,baseenv);make(p,baseenv)
subprocess.run(['codesign','--force','--sign','-',str(tools/'bin/nasm')],check=True)
for arch in ['x86_64','arm64']:
 prefix=build/('prefix-'+arch);env=baseenv.copy();env.update(CC='clang',CXX='clang++',CFLAGS=f'-arch {arch} -mmacosx-version-min=12.0 -O2',CXXFLAGS=f'-arch {arch} -mmacosx-version-min=12.0 -O2',LDFLAGS=f'-arch {arch} -mmacosx-version-min=12.0 -Wl,-adhoc_codesign',MACOSX_DEPLOYMENT_TARGET='12.0',PKG_CONFIG_PATH=str(prefix/'lib/pkgconfig'),PKG_CONFIG_LIBDIR=str(prefix/'lib/pkgconfig'))
 host=('aarch64' if arch=='arm64' else arch)+'-apple-darwin'
 for archive,name,extra in [
  ('libogg-1.3.5.tar.gz','ogg',[]),
  ('libvorbis-1.3.7.tar.gz','vorbis',['--with-ogg='+str(prefix)]),
  ('opus-1.5.2.tar.gz','opus',['--disable-doc','--disable-extra-programs','--disable-rtcd']),
  ('lame-3.100.tar.gz','lame',['--disable-frontend','--disable-decoder'])]:
  stamp=build/(name+'-'+arch+'.done')
  if stamp.exists():continue
  p=extract(archive,name+'-'+arch)
  if name=='vorbis':
   c=p/'configure';c.write_text(c.read_text().replace('-force_cpusubtype_ALL',''))
  run(['./configure','--prefix='+str(prefix),'--host='+host,'--disable-shared','--enable-static','--with-pic',*extra],p,env);make(p,env);stamp.touch()
 stamp=build/('x264-'+arch+'.done')
 if not stamp.exists():
  p=extract('x264-stable.tar.gz','x264-'+arch)
  run(['./configure','--prefix='+str(prefix),'--host='+host,'--enable-static','--enable-pic','--disable-cli','--extra-cflags='+env['CFLAGS'],'--extra-ldflags='+env['LDFLAGS']],p,env);make(p,env);stamp.touch()
 stamp=build/('vpx-'+arch+'.done')
 if not stamp.exists():
  p=extract('libvpx-1.14.1.tar.gz','vpx-'+arch)
  # Build the optimized codec for the selected macOS architecture.
  run(['./configure','--prefix='+str(prefix),'--target='+('arm64-darwin20-gcc' if arch=='arm64' else 'x86_64-darwin20-gcc'),'--disable-examples','--disable-tools','--disable-docs','--disable-unit-tests','--disable-shared','--enable-static','--enable-pic','--enable-runtime-cpu-detect'],p,env)
  # Regenerate dispatch headers after configuration changes; stale headers can
  # otherwise select AVX-512 or ARM extensions unconditionally.
  run(['make','clean'],p,env)
  for header in ['vpx_dsp_rtcd.h','vp8_rtcd.h','vp9_rtcd.h']:(p/header).unlink(missing_ok=True)
  make(p,env);stamp.touch()
 for archive,name,options in [
  ('freetype-2.13.3.tar.xz','freetype',['-DFT_DISABLE_ZLIB=ON','-DFT_DISABLE_BZIP2=ON','-DFT_DISABLE_PNG=ON','-DFT_DISABLE_HARFBUZZ=ON','-DFT_DISABLE_BROTLI=ON']),
  ('harfbuzz-10.0.1.tar.gz','harfbuzz',['-DHB_BUILD_UTILS=OFF','-DHB_BUILD_SUBSET=OFF','-DHB_HAVE_FREETYPE=OFF'])]:
  stamp=build/(name+'-'+arch+'.done')
  if stamp.exists():continue
  p=extract(archive,name+'-'+arch);b=p/'_build'
  run([cmake,'-S',p,'-B',b,'-DCMAKE_POLICY_VERSION_MINIMUM=3.5','-DCMAKE_BUILD_TYPE=Release','-DBUILD_SHARED_LIBS=OFF','-DCMAKE_POSITION_INDEPENDENT_CODE=ON','-DCMAKE_OSX_ARCHITECTURES='+arch,'-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0','-DCMAKE_INSTALL_PREFIX='+str(prefix),*options],p,env)
  run([cmake,'--build',b,'--parallel','2'],p,env);run([cmake,'--install',b],p,env);stamp.touch()
 for archive,name,extra in [('fribidi-1.0.16.tar.xz','fribidi',['--disable-docs']),('libass-0.17.3.tar.xz','ass',['--disable-fontconfig'])]:
  stamp=build/(name+'-'+arch+'.done')
  if stamp.exists():continue
  p=extract(archive,name+'-'+arch)
  if name=='vorbis':
   c=p/'configure';c.write_text(c.read_text().replace('-force_cpusubtype_ALL',''))
  run(['./configure','--prefix='+str(prefix),'--host='+host,'--disable-shared','--enable-static','--with-pic',*extra],p,env);make(p,env);stamp.touch()
 stamp=build/('ffmpeg-'+arch+'.done')
 if not stamp.exists():
  p=extract('ffmpeg-7.1.tar.gz','ffmpeg-'+arch)
  opts=['./configure','--prefix='+str(prefix),'--arch='+('aarch64' if arch=='arm64' else arch),'--target-os=darwin','--cc=clang','--cxx=clang++','--enable-cross-compile','--enable-gpl','--enable-version3','--disable-autodetect','--disable-debug','--disable-doc','--disable-ffplay','--disable-ffprobe','--disable-x86asm','--enable-static','--disable-shared','--enable-pic','--enable-libass','--enable-libx264','--enable-libvpx','--enable-libopus','--enable-libvorbis','--enable-libmp3lame','--enable-videotoolbox','--enable-audiotoolbox','--enable-zlib','--pkg-config-flags=--static','--extra-cflags='+env['CFLAGS']+' -I'+str(prefix/'include'),'--extra-ldflags='+env['LDFLAGS']+' -L'+str(prefix/'lib')]
  run(opts,p,env);make(p,env);stamp.touch()
 print('DONE',arch,flush=True)
