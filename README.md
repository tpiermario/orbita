# Orbita

Convertitore locale per macOS con interfaccia nativa: trascina un file, tieni premuti **Shift + Option (⇧⌥)** e scegli un formato dalla ruota.

## Funzioni

- Conversioni e strumenti per immagini, PDF, audio, video, documenti, fogli elettronici e archivi.
- OCR tramite Apple Vision, trascrizione locale con Whisper e rimozione dello sfondo.
- Elaborazione locale dei file. I motori, quando inclusi nell’app, funzionano offline.
- Interfaccia in italiano. Catalogo completo in [STRUMENTI.txt](STRUMENTI.txt).

Orbita è un progetto indipendente, non affiliato a Clementine.

## Stato della versione 2.3

| Piattaforma | Stato |
| --- | --- |
| Mac Intel, macOS 12+ | Esecuzione e test locali completati |
| Apple Silicon, macOS 12+ | Codice ARM compilato e dipendenze verificate; collaudo su hardware reale ancora da completare |

La build locale è firmata ad hoc e non notarizzata da Apple. La versione compatta locale ha un DMG di 697.796.643 byte, circa il 32% più piccolo del precedente. **Questo repository distribuisce i sorgenti, non il DMG completo né i motori di terzi.**

## Contenuto

- `Sources/`: interfaccia Swift/AppKit, integrazione Finder, ruota e helper Vision.
- `Engine/`: catalogo, conversioni Python e protocollo di comunicazione.
- `Tests/`: test di conversione, regressione, protocollo e selezione dell’architettura.
- `Audit/`: fixture sintetiche usate dai test di regressione.
- `DEPENDENCIES.json`: versioni, archivi e hash delle dipendenze della build locale.

## Compilare l’interfaccia

Richiede macOS e Xcode Command Line Tools con SDK e compilatore Swift compatibili.

```sh
bash build.sh
```

Lo script compila l’interfaccia e l’helper Vision in formato Universal (`x86_64` + `arm64`) e copia il motore Python. **Non scarica né installa i motori di conversione**: l’app così compilata non è ancora un pacchetto di conversione completo.

Per la build completa occorre predisporre in `Orbita.app/Contents/Resources/`:

```text
Runtime/python/                         Python 3.12 e pacchetti Intel
Runtime-arm64/python/                   Python 3.12 e pacchetti ARM
Office/LibreOffice.app/                  LibreOffice Intel
Office-arm64/LibreOffice.app/            LibreOffice ARM
bin/whisper-cli                         whisper.cpp Intel
bin/arm64/whisper-cli                   whisper.cpp ARM
Models/ggml-tiny.bin                    modello Whisper tiny multilingue
Models/u2netp.onnx                      modello rimozione sfondo
```

Le versioni e le fonti sono in [THIRD-PARTY.txt](THIRD-PARTY.txt), [requirements.lock.txt](requirements.lock.txt) e [DEPENDENCIES.json](DEPENDENCIES.json). `cmake` nel lock è uno strumento di compilazione, non necessario durante l’uso dell’app. L’icona `Orbita.icns` è opzionale e non inclusa qui.

I due runtime richiedono eseguibili e librerie per la rispettiva architettura. La build locale usa Pandoc **3.1.13 Intel** e **3.1.6 ARM**, installati separatamente dal wrapper `pypandoc_binary`: non basta installare indiscriminatamente la wheel, che può includere un eseguibile inadatto. Controllare architettura e requisito minimo di macOS di ogni componente.

Dopo l’assemblaggio, firmare e verificare il pacchetto completo. Per una distribuzione pubblica del binario occorre includere gli avvisi e quanto richiesto dalle licenze delle esatte dipendenze distribuite; i soli collegamenti ai progetti upstream non sostituiscono i rispettivi sorgenti quando richiesti.

## Verifiche

Sulla build compatta locale Intel: **158 test di conversione e 40 regressioni superati**, oltre a verifica del DMG, firma, architetture, conversione di testo Unicode e ricalcolo di formule. Risultati delle conversioni in [TEST-RESULTS.json](TEST-RESULTS.json). Questi sono risultati locali, non una certificazione di tutti i Mac o di tutti i file possibili.

Dopo aver assemblato il bundle e i suoi runtime, su Intel:

```sh
PY=Orbita.app/Contents/Resources/Runtime/python/bin/python3
"$PY" -B Tests/test_engine.py test-results.json
"$PY" -B -m unittest discover -s Tests -p 'test_regressions_*.py'
"$PY" -B Tests/test_protocol.py
"$PY" -B Tests/test_architecture_routing.py
```

Su Apple Silicon usare il Python in `Runtime-arm64`. I test generano file sintetici in cartelle temporanee; alcuni richiedono i motori completi e i servizi macOS.

## Licenze

La licenza di riutilizzo del codice originale Orbita non è ancora stata scelta. La pubblicazione rende i sorgenti consultabili; non attribuisce ai componenti di terzi una licenza diversa da quella dei rispettivi autori. Gli avvisi e le licenze delle dipendenze sono elencati in [THIRD-PARTY.txt](THIRD-PARTY.txt).

## Segnalazioni

Indicare versione di macOS, processore, azione eseguita e messaggio d’errore. Allegare soltanto esempi sintetici o file che si possono condividere pubblicamente.
