# Orbita

Convertitore locale per macOS: trascina un file, tieni premuti **Shift + Option (⇧⌥)** e scegli un formato dalla ruota.

## Scarica e installa

**[Scarica Orbita 2.3.1 per Mac](https://github.com/tpiermario/orbita/releases/download/v2.3.1/Orbita-2.3.1-Universal.dmg)** · [Tutti i download e gli hash](https://github.com/tpiermario/orbita/releases/tag/v2.3.1)

Apri il DMG, trascina Orbita in Applicazioni e avvia l'app. I motori e i modelli sono inclusi: non occorre scaricarli al primo utilizzo. Gli archivi `Sources` e `Licenses` sono per consultazione e sviluppo, **non servono per installare l'app**.

L'app è firmata ad hoc, **non ha firma Developer ID né notarizzazione Apple**. Se macOS blocca il primo avvio e ti fidi della provenienza, dopo il tentativo di apertura usa Impostazioni di Sistema → Privacy e sicurezza → Apri comunque, seguendo le [istruzioni Apple](https://support.apple.com/it-it/102445). Non disattivare le protezioni del sistema. Su Mac amministrati l'opzione potrebbe non essere disponibile.

## Funzioni

- Immagini, PDF, audio, video, documenti, fogli elettronici e archivi.
- OCR con Apple Vision, trascrizione locale Whisper e rimozione dello sfondo.
- Ruota di conversione e Studio con il catalogo completo: [STRUMENTI.txt](STRUMENTI.txt).
- Interfaccia italiana, elaborazione locale. Le operazioni Pages e Keynote richiedono quelle app Apple installate.

Progetto indipendente, non affiliato a Clementine.

## Compatibilità

Richiede **macOS 12 o successivo**. Il pacchetto Universal include motori nativi per Intel e Apple Silicon.

| Piattaforma | Verifica |
| --- | --- |
| Intel | Esecuzione e test locali |
| Apple Silicon | Binari ARM e requisiti minimi controllati; test su hardware reale ancora da completare |

La versione 2.3.1 aggiunge licenze e sorgenti, il menu “Licenze e sorgenti…” e un motore FFmpeg ricompilato senza componenti non ridistribuibili. Corregge anche la selezione delle istruzioni CPU nelle conversioni WebM.

## Codice e compilazione

`Sources/` contiene l'interfaccia Swift/AppKit; `Engine/` il motore Python; `Tests/` e `Audit/` i test e le fixture sintetiche. `Assets/` contiene l'icona.

Con Xcode Command Line Tools e un SDK/compilatore Swift compatibile:

```sh
bash build.sh
```

Questo compila l'interfaccia e l'helper Vision Universal e copia il motore Python. **Non assembla da solo i runtime e tutti i convertitori**. Per l'assemblaggio completo consultare [Distribution/README.md](Distribution/README.md), [DEPENDENCIES.json](DEPENDENCIES.json) e [requirements.lock.txt](requirements.lock.txt). `cmake` nel lock è uno strumento di compilazione.

Struttura dei componenti in `Orbita.app/Contents/Resources/`:

```text
Runtime/python/                         Python e pacchetti Intel
Runtime-arm64/python/                   Python e pacchetti ARM
Office/LibreOffice.app/                 LibreOffice Intel
Office-arm64/LibreOffice.app/           LibreOffice ARM
bin/ffmpeg, bin/whisper-cli              convertitori Intel
bin/arm64/ffmpeg, bin/arm64/whisper-cli   convertitori ARM
Models/ggml-tiny.bin                    modello Whisper tiny
Models/u2netp.onnx                      modello rimozione sfondo
Licenses/                              testi e avvisi delle licenze
```

Pandoc 3.1.13 Intel e 3.1.6 ARM sono inclusi nei rispettivi pacchetti `pypandoc`. Non sostituirli indiscriminatamente con una wheel per un'altra CPU. Gli archivi sorgente delle dipendenze sono allegati alla release, con provenienza e SHA-256 nel [manifest](Distribution/SOURCE-MANIFEST.json).

## Test

I risultati delle conversioni della release sono in [TEST-RESULTS.json](TEST-RESULTS.json). Sono test locali su Intel, non una certificazione per ogni Mac o file possibile.

Dopo aver assemblato il bundle nella radice del progetto:

```sh
PY=Orbita.app/Contents/Resources/Runtime/python/bin/python3
"$PY" -B Tests/test_engine.py test-results.json
"$PY" -B -m unittest discover -s Tests -p 'test_regressions_*.py'
"$PY" -B Tests/test_protocol.py
"$PY" -B Tests/test_architecture_routing.py
```

Su Apple Silicon usare il runtime in `Runtime-arm64`.

## Licenze

Copyright 2026 Piermario Tavernise. Il codice originale e l'icona Orbita sono distribuiti sotto **[AGPL-3.0-only](LICENSE)**, senza garanzia. Le dipendenze mantengono le proprie licenze: [THIRD-PARTY.txt](THIRD-PARTY.txt).

I testi integrali, gli avvisi e i sorgenti delle dipendenze sono scaricabili gratuitamente dalla stessa release; gli avvisi sono inclusi anche nell'app. Per modificare o sostituire i componenti consultare [Distribution/README.md](Distribution/README.md).

## Segnalazioni

Indicare versione di macOS, processore, azione e messaggio d'errore. Allegare soltanto esempi sintetici o file condivisibili pubblicamente.
