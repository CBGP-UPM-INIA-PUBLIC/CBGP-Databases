from flask import Flask, request, render_template
import csv
import os

app = Flask(__name__)

# Crear el archivo CSV si no existe
CSV_general = 'respuestas2.csv'
CSV_equipo = 'equipo.csv'
CSV_financiacion = 'financiacion.csv'


@app.route('/')
def formulario():
    return render_template('form2.html')  # Renderiza el HTML

@app.route('/guardar', methods=['POST'])
def guardar():
    # Recoger los datos del formulario
    nombre = request.form.get('nombre')
    email = request.form.get('email')
    uniqid = request.form.get('uniqid')
    ext_code = request.form.get('ext_code')
    int_code = request.form.get('int_code')
    pi = request.form.get('pi')
    title = request.form.get('title')
    start = request.form.get('start')
    end = request.form.get('end')
    extension = request.form.get('extension')
    tipo = request.form.get('tipo')

    miembrosinv=request.form.getlist('member[]')
    miembroswork= request.form.getlist('member_team[]')
    group_id= request.form.get('group_id')
    grupoinv= request.form.get('grupoinv')
    institucion= request.form.get('institution')
    
    financiadora= request.form.get('financiadora')
    funding= request.form.get('funding')
    award_amount= request.form.get('award_amount')
    overhead_pct= request.form.getlist('overhead_pct')
    cbgp_pct= request.form.getlist('cbgp_pct')
    disbursement= request.form.getlist('disbursement[]')
    disbursement_year= request.form.getlist('disbursement_year[]')
    overheads= request.form.getlist('overheads[]')
    overheads_year= request.form.getlist('overheads_year[]')
    cbgpoverheads= request.form.getlist('cbgpoverheads[]')
    cbgpoverheads_year= request.form.getlist('cbgpoverheads_year[]')
    
    

    # Escribir datos y encabezados si no existen
    encabezados_general = [
        "name", "email", "uniqid", "ext_code", "int_code", "pi", "title", 
        "start", "end", "extension", "type"
    ]

    encabezados_equipo = [ 
       "uniqid", "researchteam_member", "workteam_member", "pi", "group_id", "researchgroup", "institution"]

    encabezados_financiacion = [
        "uniqid", "funding_institution", "funding", "award_amount", "total_overhead_pct", "total_cbgp_pct", "year", "annual_disbursement", "annual_overheads", "annual_cbgpoverheads"
    ]
    

    # Abre el archivo y escribe encabezados si es necesario
    escribir_encabezados_general = not os.path.isfile(CSV_general) or os.stat(CSV_general).st_size == 0
    escribir_encabezados_equipo = not os.path.isfile(CSV_equipo) or os.stat(CSV_equipo).st_size == 0
    escribir_encabezados_financiacion = not os.path.isfile(CSV_financiacion) or os.stat(CSV_financiacion).st_size == 0

    with open(CSV_general, 'a', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        if escribir_encabezados_general:
            writer.writerow(encabezados_general)
        writer.writerow([
            nombre, email, uniqid, ext_code, int_code, pi, title, 
        start, end, extension, tipo 
        ])
    with open(CSV_equipo, 'a', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        if escribir_encabezados_equipo:
            writer.writerow(encabezados_equipo)
        # Iterar sobre los miembros de investigación y escribir cada uno en una fila
        for miembro in miembrosinv:
            writer.writerow([uniqid, miembro, "", pi, group_id, grupoinv, institucion])  # "" se usa para miembroswork si no aplica
    
    # Iterar sobre los miembros de trabajo y escribir cada uno en una fila
        for miembro in miembroswork:
            writer.writerow([uniqid, "", miembro, pi, group_id, grupoinv, institucion])  # "" se usa para miembrosinv si no aplica

    with open(CSV_financiacion, 'a', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        if escribir_encabezados_financiacion:
            writer.writerow(encabezados_financiacion)
        
        all_years = set(disbursement_year + overheads_year + cbgpoverheads_year)
    
        for year in sorted(all_years):  # Iterar en orden por los años
            # Obtener las cantidades correspondientes al año actual, o "" si no existen
            if year in disbursement_year:
                i = disbursement_year.index(year)
                cantidad1 = disbursement[i]
            else:
                cantidad1 = ""

            if year in overheads_year:
                j = overheads_year.index(year)
                cantidad2 = overheads[j]
            else:
                cantidad2 = ""

            if year in cbgpoverheads_year:
                t = cbgpoverheads_year.index(year)
                cantidad3 = cbgpoverheads[t]
            else:
                cantidad3 = ""

            # Escribir la fila en el CSV
            writer.writerow([uniqid, financiadora, funding, award_amount, overhead_pct[0], cbgp_pct[0], year, cantidad1, cantidad2, cantidad3])
                

    
    return "¡Guardado con éxito!"


if __name__ == '__main__':
    app.run(debug=True)
