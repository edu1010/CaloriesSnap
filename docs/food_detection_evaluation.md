# Evaluación de detección de comidas

Evaluación local del 7 de octubre de 2026: la combinación de Food-101 general y
el modelo español obtiene **85,09% top-1 y 93,79% top-5**, frente a **73,88% y
91,03%** del int8 anterior con la misma preparación de imágenes. Son 11,21
puntos porcentuales de mejora en identificación. Top-1 significa acertar el
primer candidato; top-5, incluir la clase correcta entre cinco candidatos.

**Estas cifras no miden la exactitud de calorías ni de gramos.** Una fotografía
no determina el peso, el aceite añadido o la receta. Los gramos iniciales son
porciones orientativas de la tabla nutricional; el usuario debe confirmar el
alimento, la preparación y la cantidad. Las calorías se calculan como
`gramos × kcalPor100g / 100` y se recalculan al editar estos datos.

## Muestra y resultados

Se utiliza `training-artifacts/food-model-v5-es/manifest.jsonl` y se excluyen
todos los caminos y hashes SHA256 presentes en entrenamiento o validación
de **v4 y v5**. De 15.764 entradas de test, se descartaron 12.828 por solapamiento
y quedaron 2.936 elegibles. Con semilla `20261007` se seleccionaron 1.160
imágenes: diez por cada una de las 116 clases. Las 101 clases generales aportan
1.010 ejemplos y las quince españolas adicionales, 150.

| Modelo | Preparación | Top-1 | Top-5 |
| --- | --- | ---: | ---: |
| int8 anterior, especialista de 116 clases | Estiramiento | 73,88% | 91,03% |
| int8 anterior, especialista de 116 clases | Recorte central | 74,05% | 91,03% |
| float32 reentrenado, mismo especialista | Estiramiento | 75,52% | 92,07% |
| float32 reentrenado, mismo especialista | Recorte central | 76,21% | 92,24% |
| Enrutamiento general HF + especialista int8 | Estiramiento | **85,09%** | **93,79%** |

El enrutamiento conserva la predicción del especialista cuando su primera
clase pertenece a las quince españolas adicionales; en los demás casos utiliza
Food-101 general. Ambos modelos funcionan localmente con TFLite, sin subir la
foto. Con esta política, el subconjunto español obtiene 89,33% top-1 y 91,33%
top-5; el general, 84,46% y 94,16%. El modelo HF por sí solo obtiene 84,95% y
94,65% en las 1.010 clases admitidas, pero no cubre las quince españolas extra.

Los resultados completos, selección, hashes y predicciones están en
`training-artifacts/detection-comparison.json` y
`training-artifacts/hf-evaluation/routing-comparison.json`. Son artefactos
locales ignorados por Git; conservarlos junto a los manifiestos para auditar
esta ejecución. El especialista int8 tiene SHA256
`b4b3ea7e1a594b9965c23a77541304db4d7d806ad9a897a3b76e90e5e32e15a0`;
el float32 reentrenado de `food-model-v5-es/export`,
`339c1582b6dfb7004ffcc09b5c0cd77cc45bf9c3dba2c97b99a766d2341fba1e`.
El float32 de la raíz de v5 corresponde a un checkpoint anterior: no debe
confundirse con el de `export` al comparar cuantización.

## Modelo general y límites de la evaluación

Fuente: [ml-debi/EfficientNetB0-Food101](https://huggingface.co/ml-debi/EfficientNetB0-Food101/tree/e52a2a721d8747db4de993f51325d31f5af375fb),
revisión fija `e52a2a721d8747db4de993f51325d31f5af375fb`. Los metadatos del
repositorio declaran MIT; no se encontró un texto de licencia independiente.
El HDF5 original se verifica con SHA256
`c29128985ad70927d9e3951558e8ddbd255fe701da5e2db105cc6377d8d9cc95`.
La exportación TFLite incorporada tiene SHA256
`11ac37e0af4ea4ff154446fe875dd2c551665d4a198d64809e10662e10fdf9ba`;
su procedencia se registra en `assets/models/food101_general_provenance.json`.
La entrada es RGB, 224 × 224, valores entre 0 y 1; el modelo integra la
conversión requerida por EfficientNet. La importación valida las clases y
los objetos serializados antes de cargar el HDF5.

La auditoría detecta duplicados exactos por ruta o contenido, **no** fotos
recortadas, reescaladas, recomprimidas o visualmente similares. Tampoco se
conoce la partición de entrenamiento del modelo HF: las exclusiones verifican
los entrenamientos locales, sin acreditar independencia respecto al modelo
externo. La muestra mezcla Food-101, AI4Food, Nutrition5k y fotos españolas;
no es una prueba de fotos reales de usuarios ni de rechazo de imágenes sin
comida. Un primer ensayo de 303 imágenes se descartó como comparación válida
porque 258 coincidían con entrenamiento/validación local previo.

La inferencia de esta tabla usa TensorFlow Lite en CPU de escritorio con cuatro
hilos. El preprocesamiento del evaluador utiliza TensorFlow; diferencias de
interpolación y los filtros de confianza de Flutter pueden alterar los
resultados finales de la aplicación. Las probabilidades no están calibradas
como porcentajes de certeza y no deben interpretarse así.

El entrenamiento ahora bloquea el test publicado de Food-101, genera validación
desde el conjunto de entrenamiento y conserva ese bloqueo durante deduplicado,
límites por clase y rebalanceo. Las etiquetas heurísticas de Nutrition5k son
opcionales y se limitan a entrenamiento. Estos cambios previenen nuevas fugas;
no corrigen retroactivamente los checkpoints v4/v5 ya entrenados.

## Reproducción

Ejecutar desde la raíz del repositorio. Se necesitan los datasets y manifiestos
locales originales; sus rutas deben existir. `tooling/requirements_training.txt`
fija TensorFlow 2.16.1, NumPy y wrapt para el evaluador local. La importación
del HDF5 HF necesita un entorno separado de Python 3.10 con TensorFlow 2.10,
h5py, NumPy y Pillow; Keras 3 no carga este formato legado. El primer acceso
descarga el modelo fijado por revisión y verifica su hash.

```powershell
.venv-training/Scripts/python.exe tooling/evaluate_food_model.py `
  --manifest training-artifacts/food-model-v5-es/manifest.jsonl `
  --exclude-manifest training-artifacts/food-model-v4/manifest.jsonl `
  --model assets/models/food_classifier.tflite `
  --model training-artifacts/food-model-v5-es/export/food_classifier_float32.tflite `
  --labels assets/models/food_classifier_labels.csv `
  --per-class 10 --seed 20261007 `
  --output training-artifacts/detection-comparison.json

.venv-training-dml310/Scripts/python.exe tooling/import_hf_food_model.py `
  --output training-artifacts/hf-evaluation/tf210 `
  --audited-samples training-artifacts/detection-comparison.json

.venv-training/Scripts/python.exe tooling/benchmark_hybrid_food_model.py `
  --baseline training-artifacts/detection-comparison.json `
  --food101-model assets/models/food101_general.tflite `
  --food101-labels assets/models/food101_general_labels.csv `
  --specialist-model assets/models/food_classifier.tflite `
  --specialist-labels assets/models/food_classifier_labels.csv `
  --output training-artifacts/hf-evaluation/routing-comparison-reproduced.json

.venv-training/Scripts/python.exe -m unittest discover -s tooling -p 'test_*.py'
flutter test test/calorie_calculator_test.dart test/nutrition_coverage_test.dart
```

El evaluador guarda una caché de hashes con tamaño y fecha de modificación;
el primer examen de todos los archivos puede tardar varios minutos. Se detiene
si falta un archivo de entrenamiento/validación y no puede verificar la fuga.
El ensayo híbrido comprueba que el especialista conserva el hash del ensayo
base y reutiliza exactamente las mismas imágenes y el mismo orden.

Validación realizada: trece pruebas Python de particiones/deduplicado y selección
del test; nueve pruebas Flutter de cobertura nutricional, nombres, actualización
de calorías y rechazo de medidas inválidas. El análisis estático de los archivos
de nutrición y sus pruebas no encontró problemas. No se ha realizado una
validación con pesos y calorías reales de cada plato.
