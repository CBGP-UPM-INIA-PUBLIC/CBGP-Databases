from flask import Flask, request, render_template
import csv
import os

app = Flask(__name__)

# Crear el archivo CSV si no existe
CSV_FILE = 'respuestas1.csv'

@app.route('/')
def formulario():
    return render_template('form1.html')  # Renderiza el HTML

@app.route('/guardar', methods=['POST'])
def guardar():
    # Recoger los datos del formulario
    nombre = request.form.get('nombre')
    email = request.form.get('email')
    titulo = request.form.get('titulo')
    extcode = request.form.get('extcode')
    intcode = request.form.get('intcode')
    startdate = request.form.get('startdate')
    enddate = request.form.get('enddate')
    extension = request.form.get('extension')
    financiadora = request.form.get('financiadora')
    tipo = request.form.get('tipo')
    miembrosinv = request.form.getlist('miembro1[]')
    miembroswork = request.form.getlist('miembro2[]')
    grupoinv = request.form.get('grupoinv')
    institucion = request.form.get('institucion')
    TotalFunding = request.form.get('TotalFunding')
    overheads = request.form.getlist('overheads[]')
    CBGPoverheads = request.form.getlist('CBGPoverheads[]')
    AnnualIncome = request.form.getlist('income[]')
    AnnualOverheads = request.form.getlist('AnnualOverheads[]')
    AnnualCBGPoverheads = request.form.getlist('AnnualCBGPoverheads[]')

    # Escribir datos y encabezados si no existen
    encabezados = [
        "Nombre", "Correo Electrónico", "Título", "ExtCode", "IntCode", 
        "Start", "End", "Extension", "InstFinanciadora", "Tipo", 
        "EqInvestigacion", "EqTrabajo", "GrupoInvestigacion", "Institucion", 
        "TotalFunding", "TotalOverheads", "CBGPoverheads", 
        "AnnualIncome", "AnnualOverheads", "AnnualCBGPoverheads"
    ]

    # Abre el archivo y escribe encabezados si es necesario
    escribir_encabezados = not os.path.isfile(CSV_FILE) or os.stat(CSV_FILE).st_size == 0

    with open(CSV_FILE, 'a', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        if escribir_encabezados:
            writer.writerow(encabezados)
        writer.writerow([
            nombre, email, titulo, extcode, intcode, startdate, enddate, extension, financiadora, 
            tipo, ";".join(miembrosinv), ";".join(miembroswork), grupoinv, institucion, 
            TotalFunding, ";".join(overheads), ";".join(CBGPoverheads), 
            ";".join(AnnualIncome), ";".join(AnnualOverheads), ";".join(AnnualCBGPoverheads)
        ])
    
    return "¡Guardado con éxito!"


if __name__ == '__main__':
    app.run(debug=True)
