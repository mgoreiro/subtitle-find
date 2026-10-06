# Arquitectura

App SwiftUI nativa, empaquetada como Swift Package (sin proyecto de Xcode). `build.sh` compila en release y monta el `.app`.

```
Sources/SubtitleFind/
├── App.swift        Escena principal (Window única), menú "Acerca de", Ajustes
├── Views.swift      ContentView, filas, badges de estado, pantalla de Ajustes
├── Library.swift    Cola y flujo de trabajo (@MainActor, @Observable)
├── Models.swift     SubKind, SubState, VideoItem, MediaInfo, protocolo SubtitleProvider
├── Scanning.swift   Escaneo de carpetas, hash de OpenSubtitles, parser de nombres, puntuación, decodificación
├── IMDB.swift       Ids explícitos (carpeta/.nfo) y resolución título → id
├── Providers.swift  OpenSubtitlesProvider, SubDLProvider, HTTP con reintentos, descompresión de zips
└── Author.swift     Datos del autor y panel "Acerca de"
```

## Flujo por vídeo (`Library.process`)

1. `NameParser.parse` extrae título, año, temporada y episodio del nombre del fichero.
2. Si hay algo que buscar (el `.srt` no existe o se permite sobrescribir), se calcula el hash y se resuelve el id de IMDB (`resolveIMDB`: manual → explícito → IMDB por título).
3. Para cada `SubKind` (normal y forzado), `fetch` recorre los proveedores: busca, puntúa (`Scoring.score`), ordena y prueba los 3 mejores. Se valida que lo descargado parezca un `.srt`, se pasa a UTF-8 y se escribe de forma atómica.
4. Los estados (`SubState`) se publican en `VideoItem` y la UI se actualiza sola.

El procesado es **secuencial** a propósito, para respetar los límites de peticiones de las APIs. Los 429 se reintentan con espera (`HTTP.send`).

## Proveedores

`SubtitleProvider` define `search` y `download`. Para añadir otra fuente, implementa el protocolo y regístrala en `Library.makeProviders`.

- **OpenSubtitles:** API REST v1. Cabeceras `Api-Key` y `User-Agent`; login opcional para ampliar la cuota. Los parámetros de consulta se envían ordenados y en minúsculas, como pide la documentación. Los forzados usan `foreign_parts_only=only`; los normales, `exclude`.
- **SubDL:** consulta por `imdb_id` y, si no hay resultados, por `film_name`. Las descargas son zips que se descomprimen con `/usr/bin/unzip`; en packs de temporada se elige el episodio por `SxxExx`.

## Nombres de salida (`SubKind.outputURL`)

- Forzado → `<vídeo sin extensión>.srt`
- Normal → `<vídeo sin extensión>_es.srt`

## Icono

`tools/make_icon.swift` dibuja el icono con AppKit y genera `Resources/AppIcon.icns` y `docs/icon.png`. Se ejecuta a mano; `build.sh` solo copia el `.icns`.

## Mejoras posibles

- Guardar claves en el Llavero (con firma de desarrollador, para evitar avisos tras cada recompilación).
- Más fuentes, como Podnapisi o Subdivx, que requerirían extraer datos de sus webs.
- Detección de forzados por contenido (pocas líneas, solo diálogos en otro idioma).
- Tests automáticos del parser de nombres y de la puntuación.
