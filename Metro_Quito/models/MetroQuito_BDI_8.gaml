/**
* Name: MetroQuitoDiagram
* Description: Version con graficos estadisticos independientes en pestañas.
*/

model MetroQuitoDiagram

global {
	// --- 1. CONFIGURACIÓN BÁSICA ---
	float step <- 1 #s; 
	date starting_date <- date("2025-12-02 06:30:00");

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
	list<estacion> estaciones_sur; 
	list<estacion> estaciones_norte; 
	list<estacion> todas_estaciones; 
	
	float tiempo_ultimo_despacho <- -9999.0;
	
	// --- VARIABLES DE INTERFAZ ---
	float velocidad_tren_kmh <- 80.0; 
    float factor_velocidad <- 1.0;
	float velocidad_tren -> (velocidad_tren_kmh #km/#h) * factor_velocidad;
	
	int numero_vagones <- 6 min: 1 max: 12; 
	int capacidad_por_vagon <- 205;
	int capacidad_total_tren -> numero_vagones * capacidad_por_vagon;

	int tasa_generacion_pasajeros <- 5 min: 1 max: 50; 
	float intervalo_despacho_minutos <- 5.0 min: 1.0 max: 20.0; 

    // Variables Demanda
    int demanda_quitumbe <- 2; int demanda_recreo <- 1; int demanda_sanfrancisco <- 1;
    int demanda_uce <- 1; int demanda_carolina <- 1; int demanda_inaquito <- 1; int demanda_labrador <- 2;

    map<int, string> nombres_clave <- [
        15::"Quitumbe", 11::"Recreo", 8::"San Francisco", 6::"UCE", 
        4::"Carolina", 3::"Iñaquito", 1::"Labrador"
    ];

	// =========================================================
	//   NUEVO: VARIABLES PARA EXPORTACION DE DATOS
	// =========================================================
	string archivo_metricas_globales <- "../results/metricas_sistema.csv";
	string archivo_detalle_estaciones <- "../results/detalle_estaciones.csv";

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
		//   NUEVO: INICIALIZAR ARCHIVOS CSV (ENCABEZADOS)
		// =========================================================
		// 1. Archivo Global: Escribimos los nombres de las columnas
		save ["Ciclo", "Hora", "Total_Viajando", "Total_Esperando", "Trenes_Activos", "Capacidad_Ofertada"] 
			to: archivo_metricas_globales format: "csv" rewrite: true;
			
		// 2. Archivo Estaciones: Columnas dinámicas
		list<string> headers <- ["Ciclo", "Hora"];
		loop est over: todas_estaciones where (each.es_clave) {
			add est.nombre_real to: headers;
		}
		save headers to: archivo_detalle_estaciones format: "csv" rewrite: true;
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
		if (every(tasa_generacion_pasajeros #cycle)) {
			create pasajero {
				estacion origen <- one_of(estacion); location <- origen.location; target_station <- origen;
				final_destination <- one_of(estacion - origen);
				direccion_norte <- (final_destination.indice_ruta > origen.indice_ruta);
				current_belief <- "waiting"; ask target_station { passengers_waiting << myself; }
			}
		}
		if (every(20 #cycle)) {
			do inyectar_demanda("Quitumbe", demanda_quitumbe); do inyectar_demanda("Recreo", demanda_recreo);
			do inyectar_demanda("San Francisco", demanda_sanfrancisco); do inyectar_demanda("UCE", demanda_uce);
			do inyectar_demanda("Carolina", demanda_carolina); do inyectar_demanda("Iñaquito", demanda_inaquito);
			do inyectar_demanda("Labrador", demanda_labrador);
		}
	}

	action inyectar_demanda(string nombre_est, int nivel_demanda) {
		if (nivel_demanda > 0) {
			int cantidad <- rnd(0, int(nivel_demanda / 2)); 
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
	//   NUEVO: REFLEX PARA GUARDAR DATOS CADA MINUTO (60 cycles)
	// =========================================================
	reflex exportar_datos_estadisticos when: every(60 #cycles) {
		
		// 1. CALCULAR DATOS GLOBALES
		int total_viajando <- sum(tren collect length(each.passengers_onboard));
		int total_esperando <- sum(estacion collect length(each.passengers_waiting));
		int trenes_activos <- length(tren where (each.estado != "en_cochera"));
		int capacidad_actual <- trenes_activos * capacidad_total_tren;
		string hora_actual <- string(current_date, "HH:mm:ss");

		// Guardar en el CSV Global (rewrite: false para AÑADIR fila, no borrar)
		save [cycle, hora_actual, total_viajando, total_esperando, trenes_activos, capacidad_actual] 
			to: archivo_metricas_globales format: "csv" rewrite: false;

		// 2. CALCULAR DATOS POR ESTACION
		// Creamos una lista que empieza con ciclo y hora
		list<string> data_estaciones <- [string(cycle), hora_actual];
		
		// Recorremos las estaciones en el mismo orden que el encabezado (solo las claves)
		loop est over: todas_estaciones where (each.es_clave) {
			add string(length(est.passengers_waiting)) to: data_estaciones;
		}
		
		// Guardar en el CSV de Estaciones
		save data_estaciones to: archivo_detalle_estaciones format: "csv" rewrite: false;
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
            draw square(tamano + 10) color: #transparent border: #red width: 3;
            draw string(length(passengers_waiting)) at: location + {-10,10} color: #black font: font("Arial", 12, #bold) perspective: false;
        }

        if (es_clave) {
            point pos_etiqueta <- location + {80, 0, 10}; 
            float ancho_boton <- (length(nombre_real) * 14.0) + 20;
            float alto_boton <- 40.0;
            draw rectangle(ancho_boton, alto_boton) at: pos_etiqueta color: #white border: #black; 
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
				if (i = (numero_vagones - 1)) {
					point punta_flecha <- pos_vagon + (vector_dir * 25);
					float dx_perp <- cos(heading + 90) * 7;
					float dy_perp <- sin(heading + 90) * 7;
					draw polygon([pos_vagon + (vector_dir * 20), punta_flecha + {dx_perp, dy_perp}, punta_flecha - {dx_perp, dy_perp}]) color: #red border: #red;
				}
			}
			point pos_msg <- location + {0, -60, 20}; 
			if (lleno) {
				draw "LLENO" at: pos_msg color: #red font: font("Arial", 18, #bold) anchor: #center perspective: false;
			} else {
				draw "Espacio: " + (capacidad_total_tren - length(passengers_onboard)) 
					at: pos_msg color: #lightgreen font: font("Arial", 14, #bold) anchor: #center perspective: false;
			}
			draw ruta_display at: location + {0, 40} color: color_texto font: font("Arial", 16, #bold) perspective: false;
		} else {
			draw circle(10) color: #darkgray at: location;
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
	reflex ride when: current_belief = "on_train" { }
	aspect base { 
		if (current_belief = "waiting") { 
			draw circle(8) color: direccion_norte ? #blue : #orange; 
		} 
	}
}

// =================================================================================
// SECCION DE EXPERIMENTO Y GRAFICOS
// =================================================================================
experiment Visualizacion type: gui {
	// Parametros originales
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Configuracion Tren" min: 20.0 max: 120.0;
    parameter "Numero Vagones" var: numero_vagones category: "Configuracion Tren" min: 1 max: 12; 
    parameter "Intervalo Salida (min)" var: intervalo_despacho_minutos category: "Configuracion Tren" min: 1.0 max: 20.0;
    parameter "Tasa Llegada General" var: tasa_generacion_pasajeros category: "Configuracion Pasajeros" min: 1 max: 50; 
    parameter "Velocidad Simulacion" var: factor_velocidad category: "Sistema" min: 0.1 max: 20.0;

    // Parametros Demanda
    parameter "Demanda Quitumbe" var: demanda_quitumbe category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Recreo" var: demanda_recreo category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda San Francisco" var: demanda_sanfrancisco category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda UCE" var: demanda_uce category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Carolina" var: demanda_carolina category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Iñaquito" var: demanda_inaquito category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Labrador" var: demanda_labrador category: "Control Demanda Estaciones" min: 0 max: 10;

	output {
		// Layout "split" permite ver las ventanas separadas si se configuran preferencias
		// pero con displays separados, GAMA crea pestañas (Tabs) automaticamente.
		layout #split;
		
		// -----------------------------------------------------
		// 1. EL MAPA PRINCIPAL
		// -----------------------------------------------------
		display "Mapa Metro" type: opengl background: #gray {
			grid mapa_densidad transparency: 0.6;
			graphics "Vias" {
				loop g over: lista_edificios { draw g color: #darkgray wireframe: true; }
				loop g over: lista_principales { draw g color: rgb(255, 200, 120) width: 2; }
				loop g over: lista_secundarias { draw g color: rgb(170, 170, 190); }
				loop g over: formas_metro { draw g color: #white width: 6; } 
			}
			species estacion aspect: base;
			species tren aspect: base;
			species pasajero aspect: base;
			
			graphics "Reloj" {
				draw "Hora: " + string(current_date, "HH:mm:ss") at: {100, 100} color: #white font: font("Arial", 24, #bold);
			}
		}

		// -----------------------------------------------------
		// 2. GRAFICO DE LINEAS (EVOLUCION DE COLAS)
		// Muestra como crecen las colas en estaciones clave
		// -----------------------------------------------------
		display "Grafico: Lineas de Tiempo" refresh: every(2 #cycles) {
			chart "Evolucion de Pasajeros Esperando" type: series {
				data "Quitumbe" value: length((todas_estaciones first_with (each.nombre_real = "Quitumbe")).passengers_waiting) color: #red marker: false style: line;
				data "Recreo" value: length((todas_estaciones first_with (each.nombre_real = "Recreo")).passengers_waiting) color: #orange marker: false style: line;
				data "San Francisco" value: length((todas_estaciones first_with (each.nombre_real = "San Francisco")).passengers_waiting) color: #yellow marker: false style: line;
				data "Carolina" value: length((todas_estaciones first_with (each.nombre_real = "Carolina")).passengers_waiting) color: #green marker: false style: line;
				data "Labrador" value: length((todas_estaciones first_with (each.nombre_real = "Labrador")).passengers_waiting) color: #blue marker: false style: line;
			}
		}

		// -----------------------------------------------------
		// 3. HISTOGRAMA (RANKING DE CONGESTION)
		// Muestra barras de las estaciones más llenas
		// -----------------------------------------------------
		display "Grafico: Ranking Congestion" refresh: every(5 #cycles) {
			chart "Estaciones con mayor demanda (Tiempo Real)" type: histogram {
				loop est over: todas_estaciones where (each.es_clave) {
					// Rojo si hay mas de 30 personas, Cian si no.
					rgb color_barra <- (length(est.passengers_waiting) > 30) ? #red : #cyan;
					data est.nombre_real value: length(est.passengers_waiting) color: color_barra;
				}
			}
		}

		// -----------------------------------------------------
		// 4. GRAFICO DE PASTEL (DISTRIBUCION TOTAL)
		// Muestra cuantos viajan al norte, sur, o esperan
		// -----------------------------------------------------
		display "Grafico: Distribucion Global" refresh: every(5 #cycles) {
			chart "Estado de los Pasajeros" type: pie {
				data "Viajando Norte" value: sum(tren where (each.direccion_norte) collect length(each.passengers_onboard)) color: #blue;
				data "Viajando Sur" value: sum(tren where (!each.direccion_norte) collect length(each.passengers_onboard)) color: #orange;
				data "Esperando en Anden" value: sum(estacion collect length(each.passengers_waiting)) color: #gray;
			}
		}
		
		// -----------------------------------------------------
		// 5. EFICIENCIA (CAPACIDAD VS USO)
		// Muestra si el metro va lleno o vacio
		// -----------------------------------------------------
		display "Grafico: Eficiencia Operativa" refresh: every(2 #cycles) {
			chart "Ocupacion Total vs Capacidad Disponible" type: series {
				// Area verde: Pasajeros reales
				data "Pasajeros a Bordo" value: sum(tren collect length(each.passengers_onboard)) color: #green style: area;
				// Linea negra: Capacidad maxima de los trenes activos (no en cochera)
				data "Capacidad Ofertada" value: length(tren where (each.estado != "en_cochera")) * capacidad_total_tren color: #black style: line;
			}
		}
	}
}