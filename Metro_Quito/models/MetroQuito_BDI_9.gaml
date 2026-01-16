/**
* Name: MetroQuitoDiagram
* Description: Version con aceleracion de tiempo, reporte horario y guardado de imagenes.
*/

model MetroQuitoDiagram

global {
	// --- 1. CONFIGURACIÓN DE TIEMPO ---
	// CAMBIO CLAVE: Aumentamos el paso de tiempo. 
	// 1 ciclo de computo = 10 segundos de la vida real. Esto acelera la simulación x10.
	float step <- 10 #s; 
	
	// Hora de inicio según horario Metro (05:00 AM)
	date starting_date <- date("2025-12-02 05:00:00");
	
	// Variable para detectar el cambio de hora para el reporte
	int hora_anterior <- -1;

	// --- 2. CARGA DE ARCHIVOS ---
	file file_edificios <- file("../includes/edificios.shp");
	file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
	file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");	
	file file_principales <- file("../includes/principales.shp");
	file file_secundarias <- file("../includes/secundarias.shp");
	file file_metro <- file("../includes/ruta_metro.shp");

	geometry shape <- envelope(file_edificios);

	// --- 3. VARIABLES GLOBALES ---
	graph red_vial;
	graph red_metro;
	
	list<geometry> lista_edificios <- file_edificios.contents;
	list<geometry> lista_principales <- file_principales.contents;
	list<geometry> lista_secundarias <- file_secundarias.contents;
	list<geometry> formas_metro <- file_metro.contents;

	estacion estacion_quitumbe;
	estacion estacion_labrador;
	list<estacion> todas_estaciones; 
	
	float tiempo_ultimo_despacho <- -9999.0;
	
	// --- VARIABLES DE INTERFAZ (SLIDERS) ---
	float velocidad_tren_kmh <- 80.0; 
	float velocidad_tren -> (velocidad_tren_kmh #km/#h); // GAMA ajusta esto automaticamente segun el 'step'
	
	int numero_vagones <- 6 min: 1 max: 12; 
	int capacidad_por_vagon <- 205;
	int capacidad_total_tren -> numero_vagones * capacidad_por_vagon;

	int tasa_generacion_pasajeros <- 15 min: 1 max: 100; // Ajustado para step de 10s
	float intervalo_despacho_minutos <- 5.0 min: 1.0 max: 20.0; 

    // Variables Demanda
    int demanda_quitumbe <- 2; int demanda_recreo <- 1; int demanda_sanfrancisco <- 1;
    int demanda_uce <- 1; int demanda_carolina <- 1; int demanda_inaquito <- 1; int demanda_labrador <- 2;

    map<int, string> nombres_clave <- [
        15::"Quitumbe", 11::"Recreo", 8::"San Francisco", 6::"UCE", 
        4::"Carolina", 3::"Iñaquito", 1::"Labrador"
    ];

	// =========================================================
	//   VARIABLES PARA EXPORTACION DE DATOS
	// =========================================================
	string archivo_metricas_globales <- "../results/metricas_minuto_a_minuto.csv";
	string archivo_detalle_estaciones <- "../results/detalle_estaciones.csv";
	
	// NUEVOS ARCHIVOS
	string archivo_parametros <- "../results/parametros_escenario.csv";
	string archivo_resumen_horario <- "../results/resumen_horario.csv";

	init {
		// A. Grafos y Limpieza
		red_vial <- as_edge_graph(file_rutas_todas);
		list<geometry> lineas_crudas <- list<geometry>(file_metro.contents);
		list<geometry> lineas_metro_limpias <- clean_network(lineas_crudas, 5.0, true, true);
		red_metro <- as_edge_graph(lineas_metro_limpias);
		geometry geom_metro_unificada <- union(lineas_metro_limpias);

		// B. Crear Estaciones
		create estacion from: file_estaciones { passengers_waiting <- []; }
		todas_estaciones <- estacion sort_by (each.location.y);
		
		loop i from: 0 to: length(todas_estaciones) - 1 {
            estacion est <- todas_estaciones[i];
            est.indice_ruta <- i; 
            est.id_visual <- i + 1; 
            if (nombres_clave contains_key (est.id_visual)) {
                est.nombre_real <- nombres_clave[est.id_visual];
                est.es_clave <- true;
            } else {
                est.nombre_real <- "E-" + string(est.id_visual);
            }
            // Asegurar que la estación esté exactamente sobre la línea
            est.location <- (geom_metro_unificada closest_points_with est.location)[0];
        }
        estacion_quitumbe <- todas_estaciones first_with (each.nombre_real = "Quitumbe");
        estacion_labrador <- todas_estaciones first_with (each.nombre_real = "Labrador");

		// C. Crear Trenes
		create tren number: 9 {
			location <- estacion_quitumbe.location;
			origen_base <- estacion_quitumbe;
			destino_base <- estacion_labrador;
			direccion_norte <- true;
			estado <- "en_cochera"; passengers_onboard <- []; heading <- 90.0;
		}
		create tren number: 9 {
			location <- estacion_labrador.location;
			origen_base <- estacion_labrador;
			destino_base <- estacion_quitumbe;
			direccion_norte <- false;
			estado <- "en_cochera"; passengers_onboard <- []; heading <- 270.0; 
		}

		// =========================================================
		//   INICIALIZAR ARCHIVOS CSV
		// =========================================================
		
		// 1. Guardar los Parametros del escenario (Sliders)
		save ["PARAMETRO", "VALOR"] to: archivo_parametros format: "csv" rewrite: true;
		save ["Velocidad Tren (km/h)", velocidad_tren_kmh] to: archivo_parametros format: "csv" rewrite: false;
		save ["Numero Vagones", numero_vagones] to: archivo_parametros format: "csv" rewrite: false;
		save ["Intervalo Despacho (min)", intervalo_despacho_minutos] to: archivo_parametros format: "csv" rewrite: false;
		save ["Demanda Quitumbe", demanda_quitumbe] to: archivo_parametros format: "csv" rewrite: false;
		save ["Demanda Labrador", demanda_labrador] to: archivo_parametros format: "csv" rewrite: false;
		// ... puedes agregar el resto de demandas aqui

		// 2. Archivos de datos continuos
		save ["Ciclo", "Hora", "Total_Viajando", "Total_Esperando", "Trenes_Activos", "Capacidad_Ofertada"] 
			to: archivo_metricas_globales format: "csv" rewrite: true;
			
		list<string> headers <- ["Ciclo", "Hora"];
		loop est over: todas_estaciones where (each.es_clave) { add est.nombre_real to: headers; }
		save headers to: archivo_detalle_estaciones format: "csv" rewrite: true;
		
		// 3. Archivo Resumen Horario
		save ["Hora_Fin", "Promedio_Esperando", "Maximo_Esperando_Simultaneo", "Total_Trenes_Activos_Fin_Hora"] 
			to: archivo_resumen_horario format: "csv" rewrite: true;
			
		hora_anterior <- starting_date.hour;
	}
	
	// --- LOGICA DE DESPACHO ---
	reflex sistema_despacho {
		float intervalo_segundos <- intervalo_despacho_minutos * 60; 
		if ((time - tiempo_ultimo_despacho) >= intervalo_segundos) {
			tren t_sur <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_quitumbe));
			if (t_sur != nil) { ask t_sur { do iniciar_viaje(estacion_labrador); } }
			tren t_norte <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_labrador));
			if (t_norte != nil) { ask t_norte { do iniciar_viaje(estacion_quitumbe); } }
			tiempo_ultimo_despacho <- time;
		}
	}

	// --- GENERAR PASAJEROS ---
	reflex generar_pasajeros {
		// Ajuste de tasa porque ahora step es 10s. Dividimos la frecuencia.
		if (flip(tasa_generacion_pasajeros / 100.0)) { 
			create pasajero {
				estacion origen <- one_of(estacion); location <- origen.location; target_station <- origen;
				final_destination <- one_of(estacion - origen);
				direccion_norte <- (final_destination.indice_ruta > origen.indice_ruta);
				current_belief <- "waiting"; ask target_station { passengers_waiting << myself; }
			}
		}
		
		// Inyección de demanda (cada 5 minutos aprox -> 30 cycles de 10s)
		if (every(30 #cycle)) {
			do inyectar_demanda("Quitumbe", demanda_quitumbe); do inyectar_demanda("Recreo", demanda_recreo);
			do inyectar_demanda("San Francisco", demanda_sanfrancisco); do inyectar_demanda("UCE", demanda_uce);
			do inyectar_demanda("Carolina", demanda_carolina); do inyectar_demanda("Iñaquito", demanda_inaquito);
			do inyectar_demanda("Labrador", demanda_labrador);
		}
	}

	action inyectar_demanda(string nombre_est, int nivel_demanda) {
		if (nivel_demanda > 0) {
			int cantidad <- rnd(0, int(nivel_demanda * 2)); // Multiplicador ajustado por step
			if (cantidad > 0) {
				estacion est <- estacion first_with (each.nombre_real = nombre_est);
				create pasajero number: cantidad {
					location <- est.location; target_station <- est; final_destination <- one_of(estacion - est);
					direccion_norte <- (final_destination.indice_ruta > est.indice_ruta);
					current_belief <- "waiting"; ask target_station { passengers_waiting << myself; }
				}
			}
		}
	}

	// =========================================================
	//   REFLEX: REPORTES CSV (Minuto a Minuto)
	// =========================================================
	reflex exportar_datos_estadisticos when: every(6 #cycles) { // cada 60 segundos (6 ciclos * 10s)
		
		int total_viajando <- sum(tren collect length(each.passengers_onboard));
		int total_esperando <- sum(estacion collect length(each.passengers_waiting));
		int trenes_activos <- length(tren where (each.estado != "en_cochera"));
		int capacidad_actual <- trenes_activos * capacidad_total_tren;
		string hora_actual <- string(current_date, "HH:mm:ss");

		save [cycle, hora_actual, total_viajando, total_esperando, trenes_activos, capacidad_actual] 
			to: archivo_metricas_globales format: "csv" rewrite: false;

		list<string> data_estaciones <- [string(cycle), hora_actual];
		loop est over: todas_estaciones where (each.es_clave) {
			add string(length(est.passengers_waiting)) to: data_estaciones;
		}
		save data_estaciones to: archivo_detalle_estaciones format: "csv" rewrite: false;
	}

	// =========================================================
	//   REFLEX: REPORTE HORARIO (Resumen cada hora)
	// =========================================================
	reflex reporte_horario {
		if (current_date.hour != hora_anterior) {
			// La hora ha cambiado. Guardamos un resumen del estado actual.
			// Nota: Para un promedio real se necesitaria acumular variables, aqui guardamos snapshot de fin de hora
			int total_esp <- sum(estacion collect length(each.passengers_waiting));
			int max_esp <- max(estacion collect length(each.passengers_waiting));
			int trenes_act <- length(tren where (each.estado != "en_cochera"));
			
			string etiqueta_hora <- string(hora_anterior) + ":00 - " + string(current_date.hour) + ":00";
			
			save [etiqueta_hora, total_esp, max_esp, trenes_act] to: archivo_resumen_horario format: "csv" rewrite: false;
			
			hora_anterior <- current_date.hour;
		}
	}

	// =========================================================
	//   REFLEX: FIN DE SIMULACION (10 PM) -> GUARDAR FOTOS
	// =========================================================
	reflex finalizar_simulacion {
		// Verificar si son las 22:00 (10 PM) o mas tarde
		if (current_date.hour >= 22) {
			write "Fin del horario operativo (22:00). Guardando resultados...";
			
			// Guardar capturas de los Displays definidos en el Experimento
			// IMPORTANTE: Los nombres deben coincidir con los 'display' en el experimento
			save (snapshot("Mapa Metro")) to: "../snapshots/mapa_final.png";
			save (snapshot("Grafico: Lineas de Tiempo")) to: "../snapshots/grafico_lineas.png";
			save (snapshot("Grafico: Ranking Congestion")) to: "../snapshots/grafico_barras.png";
			save (snapshot("Grafico: Distribucion Global")) to: "../snapshots/grafico_pastel.png";
			save (snapshot("Grafico: Eficiencia Operativa")) to: "../snapshots/grafico_eficiencia.png";
			
			do pause; // Detiene la simulación
		}
	}
}

grid mapa_densidad width: 60 height: 60 {
    int pax_count <- 0 update: length(pasajero inside self);
    float intensidad <- 0.0 update: (pax_count / 50.0);
    rgb color <- #transparent update: (pax_count = 0) ? #transparent : blend(#green, #red, (intensidad > 1.0 ? 1.0 : intensidad));
}

species estacion {
    string nombre_real;
    int id_visual;
    int indice_ruta; 
    bool es_clave <- false;
    list<pasajero> passengers_waiting;

    aspect base {
        int tamano <- es_clave ? 70 : 40;
        rgb color_estacion <- es_clave ? #yellow : #cyan;
        draw square(tamano) color: color_estacion border: #black;

        if (!empty(passengers_waiting)) {
            // Indicador visual de congestión
            rgb color_alerta <- (length(passengers_waiting) > 50) ? #red : ((length(passengers_waiting) > 20) ? #orange : #green);
            draw square(tamano + 10) color: #transparent border: color_alerta width: 3;
            draw string(length(passengers_waiting)) at: location + {-10,10} color: #black font: font("Arial", 12, #bold) perspective: false;
        }

        if (es_clave) {
            point pos_etiqueta <- location + {80, 0, 10}; 
            float ancho_boton <- (length(nombre_real) * 14.0) + 20;
            draw rectangle(ancho_boton, 40.0) at: pos_etiqueta color: #white border: #black; 
            draw nombre_real at: pos_etiqueta color: #black font: font("Arial", 16, #bold) anchor: #center; 
        }
    }
}

species tren skills: [moving] {
	string estado; 
	estacion origen_base;
	estacion destino_base;
	estacion target_station; 
	path camino_actual;
	list<pasajero> passengers_onboard;
	bool direccion_norte; 
	string ruta_display <- "";
	rgb color_texto <- #blue;

	action iniciar_viaje (estacion destino_objetivo) {
		estado <- "movimiento";
		target_station <- destino_objetivo;
		camino_actual <- path_between(red_metro, location, target_station.location);
		if (destino_objetivo.nombre_real = "Labrador") { 
			ruta_display <- "Q >> L"; color_texto <- #blue; 
			direccion_norte <- true;
		} 
		else { 
			ruta_display <- "L >> Q"; color_texto <- #orange; 
			direccion_norte <- false;
		}
		if (camino_actual = nil) { estado <- "en_cochera"; }
	}

	reflex movimiento when: estado = "movimiento" {
		// La velocidad se ajusta automaticamente con el step
		if (camino_actual != nil) { do follow path: camino_actual speed: velocidad_tren; }
		if (!empty(passengers_onboard)) { ask passengers_onboard { location <- myself.location; } }

		estacion est <- estacion closest_to self;
		if (self distance_to est < 80) { do gestionar_pasajeros(est); }

		if (location distance_to target_station < 80) {
			if (target_station = destino_base) { do iniciar_viaje(origen_base); } 
			else {
				ask passengers_onboard { do die; }
				passengers_onboard <- [];
				estado <- "en_cochera";
				camino_actual <- nil;
				ruta_display <- ""; 
			}
		}
	}

	action gestionar_pasajeros (estacion est) {
		list<pasajero> bajar <- passengers_onboard where (each.final_destination = est);
		if (!empty(bajar)) {
			ask bajar { do die; }
			passengers_onboard <- passengers_onboard - bajar;
		}

		int ocupados <- length(passengers_onboard);
		int cupo <- capacidad_total_tren - ocupados;
		
		if (cupo > 0 and !empty(est.passengers_waiting)) {
			bool mi_direccion <- direccion_norte;
			list<pasajero> candidatos <- est.passengers_waiting where (each.direccion_norte = mi_direccion);
			
			int n <- min([cupo, length(candidatos)]);
			if (n > 0) {
				list<pasajero> suben <- candidatos copy_between(0, n);
				ask suben {
					myself.passengers_onboard << self;
					current_belief <- "on_train";
					location <- myself.location; 
				}
				est.passengers_waiting <- est.passengers_waiting - suben;
			}
		}
	}

	aspect base {
		if (estado != "en_cochera") {
			rgb color_vagon <- #white;
			bool lleno <- (length(passengers_onboard) >= capacidad_total_tren);
			rgb color_borde <- lleno ? #red : #darkgreen;
			
			float largo_vagon <- 50.0; float ancho_vagon <- 15.0; float separacion <- 52.0; 
			point vector_dir <- {cos(heading), sin(heading)};
			float offset_inicial <- -1 * ((numero_vagones - 1) * separacion) / 2.0;

			loop i from: 0 to: numero_vagones - 1 {
				float mi_offset <- offset_inicial + (i * separacion);
				point pos_vagon <- location + (vector_dir * mi_offset);
				draw rectangle(largo_vagon, ancho_vagon) color: color_vagon border: color_borde rotate: heading at: pos_vagon;
			}
			point pos_msg <- location + {0, -60, 20}; 
			if (lleno) {
				draw "LLENO" at: pos_msg color: #red font: font("Arial", 18, #bold) anchor: #center perspective: false;
			}
			draw ruta_display at: location + {0, 40} color: color_texto font: font("Arial", 16, #bold) perspective: false;
		}
	}
}

species pasajero skills: [moving] control: simple_bdi {
	estacion target_station;
	estacion final_destination;
	bool direccion_norte; 
	string current_belief <- "walking_to_station";

	reflex walk when: current_belief = "walking_to_station" {
		if (location distance_to target_station < 30) {
			current_belief <- "waiting";
			ask target_station { passengers_waiting << myself; }
		}
	}
	aspect base { 
		if (current_belief = "waiting") { 
			draw circle(8) color: direccion_norte ? #blue : #orange; 
		} 
	}
}

experiment Visualizacion type: gui {
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Configuracion Tren" min: 20.0 max: 120.0;
    parameter "Numero Vagones" var: numero_vagones category: "Configuracion Tren" min: 1 max: 12; 
    parameter "Intervalo Salida (min)" var: intervalo_despacho_minutos category: "Configuracion Tren" min: 1.0 max: 20.0;
    parameter "Tasa Pasajeros (x10)" var: tasa_generacion_pasajeros category: "Pasajeros" min: 1 max: 100; 
    
    // DEMANDA
    parameter "Demanda Quitumbe" var: demanda_quitumbe category: "Demanda" min: 0 max: 10;
    parameter "Demanda Labrador" var: demanda_labrador category: "Demanda" min: 0 max: 10;
    parameter "Demanda Recreo" var: demanda_recreo category: "Demanda" min: 0 max: 10;
    parameter "Demanda San Francisco" var: demanda_sanfrancisco category: "Demanda" min: 0 max: 10;
    parameter "Demanda UCE" var: demanda_uce category: "Demanda" min: 0 max: 10;
    parameter "Demanda Carolina" var: demanda_carolina category: "Demanda" min: 0 max: 10;
    parameter "Demanda Iñaquito" var: demanda_inaquito category: "Demanda" min: 0 max: 10;

	output {
		layout #split;
		
		display "Mapa Metro" type: opengl background: #gray {
			grid mapa_densidad transparency: 0.6;
			graphics "Vias" {
				loop g over: lista_edificios { draw g color: #darkgray wireframe: true; }
				loop g over: formas_metro { draw g color: #white width: 6; } 
			}
			species estacion aspect: base;
			species tren aspect: base;
			species pasajero aspect: base;
			graphics "Reloj" {
				draw "Hora: " + string(current_date, "HH:mm:ss") at: {100, 100} color: #white font: font("Arial", 24, #bold);
			}
		}

		display "Grafico: Lineas de Tiempo" refresh: every(10 #cycles) {
			chart "Evolucion de Pasajeros Esperando" type: series {
				data "Quitumbe" value: length((todas_estaciones first_with (each.nombre_real = "Quitumbe")).passengers_waiting) color: #red marker: false style: line;
				data "Recreo" value: length((todas_estaciones first_with (each.nombre_real = "Recreo")).passengers_waiting) color: #orange marker: false style: line;
				data "San Francisco" value: length((todas_estaciones first_with (each.nombre_real = "San Francisco")).passengers_waiting) color: #yellow marker: false style: line;
				data "Carolina" value: length((todas_estaciones first_with (each.nombre_real = "Carolina")).passengers_waiting) color: #green marker: false style: line;
				data "Labrador" value: length((todas_estaciones first_with (each.nombre_real = "Labrador")).passengers_waiting) color: #blue marker: false style: line;
			}
		}

		display "Grafico: Ranking Congestion" refresh: every(20 #cycles) {
			chart "Estaciones con mayor demanda" type: histogram {
				loop est over: todas_estaciones where (each.es_clave) {
					rgb color_barra <- (length(est.passengers_waiting) > 50) ? #red : #cyan;
					data est.nombre_real value: length(est.passengers_waiting) color: color_barra;
				}
			}
		}

		display "Grafico: Distribucion Global" refresh: every(20 #cycles) {
			chart "Estado de los Pasajeros" type: pie {
				data "Viajando Norte" value: sum(tren where (each.direccion_norte) collect length(each.passengers_onboard)) color: #blue;
				data "Viajando Sur" value: sum(tren where (!each.direccion_norte) collect length(each.passengers_onboard)) color: #orange;
				data "Esperando en Anden" value: sum(estacion collect length(each.passengers_waiting)) color: #gray;
			}
		}
		
		display "Grafico: Eficiencia Operativa" refresh: every(10 #cycles) {
			chart "Ocupacion Total vs Capacidad Ofertada" type: series {
				data "Pasajeros a Bordo (Demanda)" value: sum(tren collect length(each.passengers_onboard)) color: #green style: area;
				data "Capacidad Ofertada (Oferta)" value: length(tren where (each.estado != "en_cochera")) * capacidad_total_tren color: #black style: line;
			}
		}
	}
}