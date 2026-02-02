from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from ontology import get_forms  # Función que obtiene las preguntas y sus metadatos
from collections import defaultdict
import pandas as pd
import os
import uvicorn

app = FastAPI()
templates = Jinja2Templates(directory="templates")

# Definir la carpeta de guardado para los CSV
SAVE_DIR = "data"
os.makedirs(SAVE_DIR, exist_ok=True)

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    # Obtener las preguntas desde la ontología
    data = get_forms()
    if not data:
        return HTMLResponse(content="Error cargando datos desde la ontología", status_code=500)
    
    # Agrupar las preguntas por xlabel (categoría)
    grouped_options = defaultdict(list)
    for option in data:
        xlabel = option["xlabel"]  
        question=option["questionlabel"]
        grouped_options[xlabel].append(option)
    
    return templates.TemplateResponse("form.html", {"request": request, "grouped_options": grouped_options.items()})

@app.post("/submit")
async def save_responses(request: Request):
    form_data = await request.form()
    print("📥 Datos Recibidos:", dict(form_data))  # Verificar
    
    # Agrupar las respuestas por xlabel y pregunta
    grouped_answers = defaultdict(lambda: defaultdict(list))

    for key, value in form_data.items():
        # Extraer xlabel y pregunta usando '__' como separador
        if "__" in key:
            xlabel, question = key.split("__", 1)
        else:
            xlabel, question = "General", key  # Si no tiene '__', usar "General"
        
        # Agregar la respuesta al grupo correspondiente por xlabel y pregunta
        grouped_answers[xlabel][question].append(value)

    # Guardar las respuestas por xlabel en archivos separados
    for xlabel, questions in grouped_answers.items():
        # Crear una lista de preguntas y respuestas agrupadas
        preguntas = list(questions.keys())  # Las preguntas serán las columnas
        respuestas = []

        # Determinar el número máximo de respuestas
        max_respuestas = max(len(answers) for answers in questions.values())

        # Construir las filas de respuestas
        for i in range(max_respuestas):
            fila = []
            for pregunta in preguntas:
                # Para cada pregunta, agregar la respuesta correspondiente
                if i < len(questions[pregunta]):
                    fila.append(questions[pregunta][i])  # Añadir respuesta a la fila
                else:
                    fila.append('')  # Si no hay respuesta, agregar vacío
            respuestas.append(fila)

        # Crear el DataFrame con las preguntas como columnas
        df = pd.DataFrame(respuestas, columns=preguntas)

        # Guardar el DataFrame en un archivo CSV por xlabel
        filename = os.path.join(SAVE_DIR, f"respuestas_{xlabel.replace(' ', '_')}.csv")
        print(f"📂 Guardando en: {filename}")  # Muestra la ruta del archivo

        # Si el archivo ya existe, agregamos las respuestas nuevas sin sobrescribir los datos previos
        if os.path.exists(filename):
            df.to_csv(filename, mode="a", header=False, index=False)
        else:
            df.to_csv(filename, mode="w", header=True, index=False)

    print("✅ Guardado completado")  # Confirmación final
    return {"message": "Respuestas guardadas correctamente"}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=5000, reload=True)


####  uvicorn app:app --host 127.0.0.1 --port 5000 --reload  ##Terminal en ubicación de app.py



