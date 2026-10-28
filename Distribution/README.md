# Distribuzione di Orbita 2.3.1

Il codice originale di Orbita è distribuito sotto AGPL-3.0-only. I componenti esterni mantengono le proprie licenze. I testi integrali sono nel pacchetto di avvisi allegato alla release e in `Orbita.app/Contents/Resources/Licenses`.

## Sorgenti dei componenti

Gli archivi `Orbita-2.3.1-Sources-*` allegati alla stessa release contengono le distribuzioni sorgente delle dipendenze, incluse le versioni di FFmpeg e delle sue librerie usate nella compilazione pubblica. `SOURCE-MANIFEST.json` identifica ogni archivio con origine e SHA-256. Gli archivi dei sorgenti sono separati dal DMG: non servono per utilizzare l'app offline.

Per modificare l'interfaccia, eseguire `bash build.sh` dalla radice del repository. Per compilare il motore video, estrarre l'archivio che contiene `sources/` accanto a `build_ffmpeg.py`, installare Xcode Command Line Tools e CMake, quindi eseguire `python3 build_ffmpeg.py`. Il risultato è in `build/prefix-x86_64/bin/ffmpeg` e `build/prefix-arm64/bin/ffmpeg`. Lo script compila anche le librerie richieste, senza `--enable-nonfree`. Una modifica di compatibilità rimuove dal configure di libvorbis un'opzione del linker non più supportata: è applicata esplicitamente dallo script.

Gli altri componenti sono distribuzioni upstream: i loro archivi comprendono le istruzioni di compilazione e gli script originali. PyMuPDF 1.26.7 usa MuPDF 1.26.12. Pandoc usa le versioni distinte 3.1.13 (Intel) e 3.1.6 (ARM). LibreOffice 25.8.7.2 include i suoi sorgenti, dizionari, traduzioni e archivi delle dipendenze esterne. Python 3.12.15 proviene da python-build-standalone 20261021; le relative ricette, patch e licenze sono incluse.

## Modificare o sostituire i componenti

La distribuzione non impone restrizioni al reverse engineering necessario per modificare o fare debug delle librerie LGPL. I moduli Python e le librerie dinamiche possono essere sostituiti nelle cartelle `Runtime` e `Runtime-arm64`; mantenere l'architettura e le interfacce compatibili. Per i componenti collegati staticamente, usare i sorgenti e gli script forniti per ricompilare il relativo eseguibile. FFmpeg, Pandoc, LibreOffice e Whisper vengono avviati come processi separati.

Dopo una modifica al bundle, ricreare la firma locale con `codesign --force --deep --sign - Orbita.app` e verificarla con `codesign --verify --deep --strict Orbita.app`. Questa firma ad hoc consente di verificare l'integrità tecnica del bundle; non è una firma Developer ID né una notarizzazione Apple. Non è necessaria una chiave privata del distributore per eseguire una propria versione modificata.

## Differenze rispetto al pacchetto locale 2.3

- Sostituzione di entrambi gli eseguibili FFmpeg con compilazioni GPLv3 riproducibili tramite lo script incluso.
- Aggiunta degli avvisi, dei testi di licenza e del collegamento ai sorgenti.
- Voce “Licenze e sorgenti…” nel menu.
- Aggiornamento della versione a 2.3.1.

Le risorse inutilizzate rimosse dalla versione compatta sono elencate nel rapporto di potatura distribuito con l'app. I sorgenti upstream non sono stati rimossi dagli archivi pubblicati. Le copie duplicate nel bundle possono essere unite mediante hard link prima della creazione del DMG.

Dopo aver assemblato tutti i componenti e copiato il contenuto del pacchetto Licenses in `Contents/Resources/Licenses`, eseguire `bash package.sh`. Lo script crea un DMG ULMO e firma localmente il bundle. La release ufficiale applica inoltre hard link ai file identici per ridurre lo spazio; questa ottimizzazione non cambia i byte dei file.
