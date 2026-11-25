# Plan: reconocimiento abierto de platos con Qwen en el móvil

> Documento vivo. Si el trabajo se queda a medias, el apartado
> **[Estado](#estado)** dice exactamente por dónde va y qué falta.
> Última actualización: 2026-11-22.

## 1. Problema

Hoy la app identifica el plato con dos clasificadores TFLite (Food-101 general +
especialista español) y enruta entre ellos. Funciona (85 % top-1 en la muestra
local) pero tiene tres límites que no se arreglan reentrenando:

1. **Vocabulario cerrado: 116 platos.** Un bocata de lomo, un táper de lentejas,
   un plato combinado o un precocinado siempre acaban en la clase "menos mala".
2. **Un solo alimento por foto.** Un plato con arroz, pollo y ensalada devuelve
   una única etiqueta.
3. **Los gramos no salen de la foto.** Se usa la ración media de la tabla; la
   imagen no influye en la cantidad.

Objetivo: que detecte *cualquier* plato (bocadillo, plato preparado, combinado…)
y devuelva una estimación de calorías, **ejecutándose en el móvil y sin subir la
foto a ningún servidor**.

## 2. Decisión

**Sí a Qwen, pero como segunda etapa de una cascada y con las calorías ancladas
a la base de datos local, no inventadas por el modelo.**

```
foto ──► clasificadores TFLite (≈0,2 s, ya existen)
           │  top-3 como pistas
           ▼
        Qwen3.5 visión (GGUF, llama.cpp en el dispositivo)
           │  JSON: plato + componentes + gramos + kcal/100 g propuestas
           ▼
        Anclaje nutricional (Dart)
           │  componente → tabla local (kcal/100 g fiables)
           │  sin coincidencia → valor del modelo, acotado y marcado "estimado"
           ▼
        Pantalla de confirmación (editable, como ahora)
```

Si el modelo no está descargado, el móvil no tiene memoria suficiente, o la
inferencia falla o tarda demasiado → se usa el resultado de los clasificadores,
igual que hoy. La app nunca empeora respecto al estado actual.

### Por qué así y no otras opciones

| Opción | Veredicto |
| --- | --- |
| Seguir ampliando clases del clasificador | Descartada como vía principal: cada plato nuevo exige dataset + reentreno y nunca cubre "cualquier plato". Se mantiene como vía rápida y de reserva. |
| CLIP/SigLIP zero-shot con lista de platos | Vocabulario grande y rápido, pero sigue sin descomponer un plato en componentes ni razonar la cantidad. Posible mejora futura de la etapa 1. |
| VLM en la nube | Descartada: rompe el requisito "todo local, sin cuenta, sin coste". |
| **VLM local (Qwen3.5) + anclaje a BD** | **Elegida.** Vocabulario abierto, varios componentes, cantidades razonadas, nombres en español. |

### Modelo

Qwen3.5 "small" (marzo 2026) es multimodal nativo y tiene GGUF oficiales de la
comunidad (`unsloth/Qwen3.5-*-GGUF`). Dos niveles seleccionables en la app:

| Nivel | Ficheros | Descarga | RAM orientativa |
| --- | --- | ---: | --- |
| Ligero | `Qwen3.5-0.8B-Q4_K_M.gguf` (508 MB) + `mmproj-F16.gguf` (195 MB) | ≈ 0,7 GB | móviles de 4–6 GB |
| Preciso | `Qwen3.5-2B-Q4_K_M.gguf` (1 222 MB) + `mmproj-F16.gguf` (637 MB) | ≈ 1,9 GB | móviles de 8 GB o más |

El modelo **no va dentro del APK** (lo haría inviable): se descarga una vez
desde Ajustes, con tamaño visible, reanudación y verificación SHA-256. Después
todo funciona sin conexión.

### Runtime

`llamadart` (llama.cpp para Dart/Flutter): binarios nativos precompilados para
Android y Windows, soporte de proyector multimodal (`mmproj`) y salida JSON.
Requiere Flutter ≥ 3.38 (hay 3.41.8). El motor queda detrás de una interfaz
(`VlmEngine`) para poder cambiarlo o simularlo en tests.

### Qué NO promete esto

- Los gramos siguen siendo una **estimación visual**; el usuario confirma.
- Un modelo de 0,8–2 B se equivoca y a veces inventa. Por eso las kcal/100 g
  salen de la tabla local siempre que hay coincidencia, y todo es editable.
- Latencia: segundos-decenas de segundos por foto en CPU de móvil, frente a
  0,2 s del clasificador. Se muestra el progreso y se puede cancelar.

## 3. Fases

### Fase 0 — Plan y línea base
- [x] Revisar pipeline actual y evaluación existente (`docs/food_detection_evaluation.md`).
- [x] Elegir modelo, runtime y arquitectura (este documento).

### Fase 1 — Núcleo independiente del runtime (testeable sin modelo)
- [x] `MealAnalysis`: parser tolerante del JSON del modelo (texto alrededor,
      bloques ```json, comas finales, números como texto, `<think>`, salida
      cortada por límite de tokens) → `lib/services/food_detection/vlm/meal_analysis.dart`.
- [x] Prompt y esquema JSON (`vlm/meal_analysis_prompt.dart`) con pistas del clasificador.
- [x] `NutritionGrounding` (`vlm/nutrition_grounding.dart`): componente →
      tabla local (exacto en el idioma de la consulta, luego aproximado por
      palabras; "frito/empanado/seco" nunca se ignoran), límites de gramos y kcal.
- [x] Tabla ampliada: `lib/data/local/common_foods_es.json` (178 alimentos:
      panes, bocadillos, embutidos, guisos, precocinados, bebidas y genéricos),
      generada por `tooling/build_common_foods_es.py`.
- [x] Tests: `test/meal_analysis_test.dart`, `test/nutrition_grounding_test.dart`.

### Fase 2 — Runtime y modelos
- [x] `llamadart` 0.10.0; `LlamadartVlmEngine` (`vlm/vlm_engine.dart`) detrás
      de la interfaz `VlmEngine`.
- [x] `VlmModelCatalog` (URLs fijadas a revisión + SHA-256) y `VlmModelStore`
      (descarga reanudable con `Range`, verificación, borrado, modelo activo).
- [x] Reescalado de la foto (512 px de lado mayor) antes de la inferencia.
- [x] `pubspec.yaml → hooks.user_defines.llamadart`: solo runtime llama.cpp y
      solo CPU en Android (sin LiteRT-LM ni Vulkan) para no engordar el APK.

### Fase 3 — Integración en la app
- [x] `VlmMealAnalyzer` + `CascadeMealAnalysisService` (reserva al clasificador
      si no hay modelo, hay error, respuesta inservible o se agota el tiempo;
      el modelo se libera tras 3 min sin uso).
- [x] Pantalla **IA local** (icono ✨ en la barra de Inicio): descargar, usar,
      borrar, aviso de RAM insuficiente.
- [x] Registro de comida: progreso por etapas, varios componentes, nombre del
      plato, aviso de kcal "estimadas por el modelo".
- [x] Textos ES/EN.
- [x] Permiso `INTERNET` en el manifiesto principal de Android (faltaba: en
      release tampoco funcionaba la búsqueda en Open Food Facts).

### Fase 4 — Verificación
- [x] `flutter analyze` sin avisos; `flutter test`: 51 pasan, 2 omitidos
      (los opt-in nativos). Incluye `test/vlm_pipeline_test.dart`: descarga
      real contra un servidor HTTP local, reanudación, checksum incorrecto,
      cascada con motor simulado.
- [x] APK release arm64 compila y empaqueta `libllama.so`/`libmtmd.so`.
- [x] Benchmark nativo en Windows con el modelo real
      (`test/vlm_native_benchmark_test.dart`): identificación sobre la muestra
      auditada y **error de calorías contra Nutrition5k** (platos pesados).
- [ ] Ajustar prompt / tamaño de imagen / pistas según el benchmark.
- [x] Prueba de latencia y memoria por CPU en un POCO F3 con LFM3 y Qwen 2B.

### Fase 5 — Documentación
- [x] Actualizar `README.md` y `docs/food_detection_evaluation.md`.

## 4. Estado

Los resultados en Windows y en el POCO F3 están en
[`food_detection_evaluation.md`](food_detection_evaluation.md).

| Fecha | Hecho |
| --- | --- |
| 2026-10-07 | Plan escrito; investigación de modelo y runtime cerrada. |
| 2026-10-07 | Fases 1-3 completas y con tests. APK arm64 compila. |
| 2026-11-22 | Descripción opcional del plato: va al prompt como evidencia fuerte (`MealAnalysisPrompt.user(description:)`, máx. 300 caracteres) y genera sugerencias de ingredientes. Nueva tabla `lib/data/local/ingredients_es.json` (85 ingredientes, 201 preparaciones con macros; se genera con `tool/build_ingredients_db.py`) con buscador en la confirmación. **Sin medir aún en el benchmark con descripción.** |
| 2026-11-22 | Tabla de ingredientes pasada a valores oficiales CIQUAL 2020 (ANSES): 174 preparaciones directas, 20 derivadas (CIQUAL + aceite), 6 estimadas. |
| 2026-11-26 | Panel de primer arranque, borrador durante el análisis, registro por texto y repetición desde el historial. LFM3-VL-2B se ofrece como alternativa con `llamadart` 0.21.0. |

### Cómo retomar

```powershell
flutter analyze
flutter test
# Benchmark con el modelo real (descarga ~0,7 GB la primera vez):
$env:CALORIESNAP_VLM_BENCHMARK = '1'
$env:CALORIESNAP_VLM_MODEL = 'light'      # o 'precise' (~1,9 GB)
flutter test test/vlm_native_benchmark_test.dart
```

### Decisiones tomadas por el camino

- **Las kcal/100 g las pone la tabla, no el modelo.** El modelo solo aporta su
  cifra cuando el alimento no está en la tabla, y la app lo marca.
- **El modelo no decide solo si hay comida.** Si dice "no hay comida", no se
  añade nada pero se dejan las sugerencias del clasificador.
- **`confidence` = 0 en resultados del modelo**: no da una puntuación calibrada.
- **CPU en móvil por defecto.** Vulkan en Android es demasiado irregular entre
  fabricantes; en escritorio se usa GPU si la hay.
