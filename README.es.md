# AIPDD PhotoEditor（base Compositor）

[English](README.md) · [简体中文](README.zh-Hans.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [العربية](README.ar.md) · [Tiếng Việt](README.vi.md) · **Español** · [Русский](README.ru.md)

Adobe Photoshop cuesta demasiado y herramientas como GIMP no me resultan suficientemente familiares para mantener el flujo. Por eso construí Compositor.

El objetivo era crear un editor de imágenes completo, totalmente gratuito y de código abierto. Yo usaba Photoshop para composición y postproducción, así que Compositor está construido alrededor de ese flujo de trabajo, con las herramientas necesarias para lograr una imagen final perfecta al píxel.

Como es de código abierto, puedes descargar el proyecto de Xcode y añadir, quitar o modificar cualquier función para adaptarla a tu flujo.

## Instalación

### Descarga
Consigue Compositor en [robbietilton.com/compositor](https://robbietilton.com/compositor), o descarga la última versión directamente desde [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest).

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

## Características

### Capas
- Capas y carpetas, con opacidad y el conjunto completo de modos de fusión de Photoshop en su orden; la opacidad de una carpeta atenúa todo lo que contiene
- Máscaras de capa: píntalas, rellénalas, invierte, difumina y desvanece sus bordos en cualquier lugar del lienzo, incluso más allá de los píxeles de la propia capa; víncula o desvincula para transformar la máscara por separado
- Máscaras de recorte y máscaras de carpeta
- Capas de ajuste: Tono/Saturación, Niveles, Curvas, Exposición, Mapa de degradado, Grano, Blanco y negro, Balance de color, Invertir, Desfoque gaussiano, Desfoque de movimiento y Ruido
- Estilos de capa: Contorno, Sombra, Superposición de color, Sombra interior, Resplandor exterior y Resplandor interior, renderizados en GPU y editables en cualquier momento
- Combinar hacia abajo, Combinar capas y Combinar grupo (⌘E)
- Duplicar, renombrar en línea, reordenar y anidar arrastrando; Option-arrastre para duplicar; menú contextual en el panel Capas
- Copiar y pegar capas y carpetas enteras (⌘C/⌘V sin selección), dentro de un proyecto o entre proyectos, o arrastrarlas entre proyectos

### Transformación
- Mover, escalar, rotar e invertir sin destruir — las imágenes conservan su resolución completa por muy pequeñas que las hagas
- Distorsión libre (⌘-arrastrar un asa), con Shift para bloquear a un eje
- Transformar varias capas, o una carpeta entera, juntas
- Ajuste magnético a bordes y centros del lienzo y de las capas, con guías
- Valores exactos de posición, tamaño, escala y ángulo, ajustables con las flechas
- Voltear capa y voltear lienzo, horizontal y vertical

### Selecciones
- Marco rectangular y elíptico, lazo libre y lazo poligonal, y la herramienta inteligente — la varita mágica selecciona por color, Objeto traza lo que hagas clic (Tab para alternar)
- Seleccionar sujeto, y Expandir, Contraer y Desvanecer cualquier selección
- Añadir y sustraer selecciones, mover el contorno, o mover y duplicar los píxeles de dentro
- Cargar los píxeles de una capa o una máscara como selección
- Relleno según el contenido, que también puede extender una imagen más allá de sus bordes

### Pintura y retoque
- Pincel con tamaño, dureza, opacidad y suavizado, en modo Pintar o Borrar (B y E), y Shift para líneas rectas
- Pincel de corrector puntual (según el contenido)
- Tampón de clonado, alineado o no, tomando muestra de una capa o de todas
- Herramienta Desenfocar, sobre píxeles o máscaras
- Herramienta Degradado y Herramienta Forma (rectángulos, rectángulos redondeados, elipses y líneas), que se mantienen editables en lugar de rasterizarse
- Herramienta de Texto (T): edición multilinea en línea en cajas de párrafo arrastrables y redimensionables; fuente, tamaño, color, alineación e interlineado en la cabecera de la herramienta; transforma el texto úsalo como máscara de recorte
- Cuentagotas y un seletor de color completo

### Ajustes y filtros
- Filtro Camera Raw: luz, color, curvas, mezclador de color, corrección de color, detalle, óptica y geometría, en un panel junto al lienzo; cada sección se restablece desde su cabecera
- Niveles (con Auto), Curvas, Tono/Saturación, Exposición, Mapa de degradado, Grano, Blanco y negro, Balance de color e Invertir
- Desfoque gaussiano y Desfoque de movimiento que se extienden más allá de los bordes de la capa
- Añadir ruido, Viñeta, Bloom / Resplandor, Trama, Líneas de barrido, Contraste tonal, Corrección de lente y Quitar fondo
- Previsualizaciones en vivo, limitadas a la selección si la hay
- Último filtro (⌃⌘F) vuelve a ejecutar el último filtro con la misma configuración

### Lienzo y archivos
- Múltiples proyectos en pestañas
- Buscar comandos (⌘F): encuentra cada comando de menú y herramienta por nombre, como en Raycast u Obsidian, y ejecútalo con Return
- Alternar pantalla completa (F): solo el lienzo sobre negro ocupando toda la pantalla, con todos los paneles guardados; F o Esc los devuelve
- Reglas (⌘R), guías arrastradas desde ellas, una cuadrícula de composición con espaciado y subdivisiones ajustables, y Ajustar a para guías, cuadrícula, capas y límites del documento
- Recortar con ajuste magnético, proporciones que incluyen 3:4 y 9:16, y Option para recorte simétrico; con una selección, el recorte parte de ella
- Tamaño de lienzo, Tamaño de imagen y Recortar
- Un minimapa Navegador en la esquina del lienzo desde el 300% de zoom: el documento completo en pequeño con un recuadro alrededor de la vista; haz clic o arrastra para moverte (Ver › Navegador)
- Submuestreo nítido y de alta calidad al alejar, y cuadrícula de píxeles al acercar
- Importar JPEG, PNG, HEIC, TIFF, WebP, SVG, RAW de cámara (con un paso de revelado previo) y PSD y PSB de Photoshop (RGB de 8 bits; no CMYK). Las carpetas, máscaras, modos de fusión, rectángulos/elipses rellenos y el texto horizontal simple de Photoshop permanecen editables; otros vectores y el texto vertical se convierten en píxeles. Se muestra un informe de conversión antes de aplicar nada
- Documentos grandes: el presupuesto de memoria escala con tu Mac, y un archivo de Photoshop demasiado grande para abrirse se recorta al lienzo
- Exportar PNG (⇧⌘E), Exportar JPEG (⇧⌥⌘S) y Exportar como (⇧⌥⌘W) para PNG, JPEG o un PDF de una página a tamaño de impresión, escalado si quieres, con previsualización en vivo, calidad JPEG y tamaño de archivo; Copiar combinado
- Sigue trabajando mientras se guarda un proyecto
- Atajos de teclado al estilo Photoshop por todas partes, reasignables en Edición › Atajos de teclado
- Arrastra la etiqueta de un número para desplazar su valor, como en Photoshop
- Actualizaciones automáticas, firmadas y notariadas

### IA (con tu propia pasarela)
- La Pasarela de IA (⌘,) dirige todas las funciones de IA a cualquier servidor compatible con OpenAI en el que confíes: alojado, proxy corporativo o ejecutor local. Los canales tienen prioridad, peso, tiempo de espera, proxy HTTP/HTTPS/SOCKS opcional y anulaciones por capacidad para modelo, ruta y canal; las claves de API viven en el Llavero de macOS, nunca en un archivo de preferencias. Un canal AIPDD viene preconfigurado para que empieces solo con una clave. Probar Conexión verifica un canal antes de guardarlo
- Las capacidades son slots, no endpoints codificados: Chat de texto, Generación de imagen, Edición de imagen, Vídeo, Texto a voz, Voz a texto, Incrustaciones y Modelo de decisión eligen cada uno su propio canal y modelo, para que puedas, por ejemplo, enrutar trabajo de imagen a un proveedor y chat a otro
- Cada acción de IA es un comando de menú, así que aparece en Buscar comandos (⌘F) y se puede reasignar en Edición › Atajos de teclado
- Generar imagen: texto a imagen con tamaño, calidad, estilo, cantidad e indicación negativa; suelta los resultados sobre el lienzo como nuevas capas, o guárdalos en disco
- Edición de imagen y Relleno generativo (imagen a imagen): pasa los píxeles de la capa activa a la pasarela con una indicación, y reemplaza la capa en el sitio (deshacible, máscara preservada) o añade el resultado como nueva capa; si la capa activa tiene una máscara habilitada, esa máscara se envía también, para que el modelo edite solo lo que marcaste
- Transferencia de estilo: dale a la pasarela una imagen de referencia y una intensidad (0–100%), aplica su tono a la capa activa
- Edición en lenguaje natural: describe una edición en lenguaje corriente — "sube la saturación", "renombra a cielo", "deselecciona el sujeto", "agrupa estas capas" — el modelo de chat devuelve una intención estructurada y el editor la ejecuta por los mismos caminos de código que un clic en el menú, con un analizador por palabras clave como alternativa sin conexión. Las intenciones destructivas (eliminar, reemplazar píxeles) piden confirmación antes de actuar
- Selección semántica: el pipeline máscara-a-lienzo está conectado — una máscara de segmentación desde la pasarela se convierte o en una máscara de capa (blanco revela) o en una selección de hormigas marchando trazada a lo largo de los bordes exactos de los píxeles, colocada bajo la transformación de la capa. El modelo texto-a-máscara en sí sigue siendo un marcador de posición; los endpoints están listos para un servicio compatible con SAM
- Vídeo, Voz y Transcripción corren por la cola de tareas asíncrona: enviar → sondear con backoff exponencial → descargar. El sondeo tiene fecha límite y respeta la cancelación, así que una pasarela bloqueada ya no puede congelar el panel; un botón Cancelar suelta la tarea en su sitio
- Nada sale de tu Mac salvo hacia el canal que configuraste; la app no llama a casa, no incluye ninguna clave de API y no mide el uso

### Funciona con agentes IA
- Los agentes IA y los scripts pueden construir y editar proyectos directamente: un `.comp` es una carpeta de capas PNG y un manifiesto, y un proyecto abierto se actualiza en vivo a medida que se escribe. Ver [Escribir proyectos de Compositor](docs/writing-comp-files.md)

## Requisitos

- macOS 26.0 o posterior en un Mac con Apple silicon
- Xcode 26 o posterior (para compilar desde el código fuente)

## Traducciones

Compositor viene con ocho idiomas de interfaz — inglés, chino simplificado, francés, japonés, árabe, vietnamita, español y ruso — y puedes elegir uno explícitamente en Ajustes de la pasarela de IA › General (o dejarlo en «Seguir el sistema» para respetar el orden del sistema). La interfaz refleja la localización: el árabe pasa a diseño de derecha a izquierda en el siguiente arranque.

El catálogo de cadenas vive en `Compositor/Resources/*.lproj/Localizable.strings`, un archivo por idioma, con la cadena literal en inglés como clave. Las claves que faltan caen al inglés, así que un idioma a medio traducir sigue siendo utilizable. Se aceptan PR de hablantes nativos que rellenen huecos o mejoren la redacción existente; si tomas un idioma por primera vez, empieza por las superficies visibles (menús, hojas de IA, cabeceras de herramienta) antes de los tooltips más profundos.

## Compilación

Abre `Compositor.xcodeproj` y ejecuta el esquema **Compositor**.

## Liberación

`scripts/release.sh` compila una versión Release, la firma con Developer ID, la notariza y sella, y la empaqueta en `dist/Compositor-<versión>.dmg`.

Necesita, todo fuera de este repositorio:

- un certificado **Developer ID Application** en el llavero de inicio de sesión
- credenciales de notarización guardadas con `xcrun notarytool store-credentials "compositor-notary" …`
- [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`)

## Comunidad

Compositor se desarrolla en abierto, y la forma más rápida de influir en su rumbo es sumarse a la discusión. Mantengo un grupo pequeño en WeChat (ID: **raikkonenlxx**) para que usuarios y desarrolladores intercambien prompts, reporten errores, compartan archivos `.comp` y hablen de configuraciones de pasarela y funciones de IA. Añádeme con «Compositor» en la nota para saber que no eres un bot.

<div align="center">
  <img src="./docs/references/canvas-group-qr.png" width="260" alt="Código QR de WeChat — únete al grupo de discusión AIPDD-Agent-Claw"/>
</div>
<br>

Para los temas que deben quedar registrados — errores reproducibles, solicitudes de función, PR — ábrelos igualmente en GitHub para que la discusión sea buscable.

## Licencia

MIT — ver [LICENSE](LICENSE).
