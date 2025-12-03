/**
* Name: MetroQuito_Final_Fixed
* Description: Estructura original respetada + Correccion de direccion y errores de compilacion.
*/

model MetroQuitoFixed

global {
	// --- 1. CONFIGURACIÓN BÁSICA ---
	float step <- 1 #s; 
	// Iniciamos a las 06:30 para simular hora pico
	date starting_date <- date("2025-12-02 06:30:00");

	// --- 2. CARGA DE ARCHIVOS ---
	file file_edificios <- file("../includes/edificios.shp");
	file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
	file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");	
	file file_principales <- file("../includes/principales.shp");
	file file_secundarias <- file("../includes/secundarias.shp");
	file file_metro <- file("../includes/ruta_metro.shp");
	image_file icono_tren <- image_file("../includes/tren_metro.png");

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
	list<estacion> todas_estaciones; // Nueva lista para ordenar
	
	// Variables de control de despacho
	float tiempo_ultimo_despacho <- -9999.0;
	
	// --- VARIABLES DE INTERFAZ (ORIGINALES MANTENIDAS) ---
	float velocidad_tren_kmh <- 80.0; 
    float factor_velocidad <- 1.0;
	float velocidad_tren -> (velocidad_tren_kmh #km/#h) * factor_velocidad;
	float velocidad_pasajero <- 5.0 #km / #h;
	
	// --- MODIFICACIÓN: CAPACIDAD DINÁMICA ---
	int numero_vagones <- 6 min: 1 max: 12; 
	int capacidad_por_vagon <- 205;
	int capacidad_total_tren -> numero_vagones * capacidad_por_vagon;

	// Sliders originales
	int tasa_generacion_pasajeros <- 5 min: 1 max: 50; 
	float intervalo_despacho_minutos <- 5.0 min: 1.0 max: 20.0; 

    // --- VARIABLES DEMANDA POR ESTACIÓN ---
    int demanda_quitumbe <- 2 min: 0 max: 10;
    int demanda_recreo <- 1 min: 0 max: 10;
    int demanda_sanfrancisco <- 1 min: 0 max: 10;
    int demanda_uce <- 1 min: 0 max: 10;
    int demanda_carolina <- 1 min: 0 max: 10;
    int demanda_inaquito <- 1 min: 0 max: 10;
    int demanda_labrador <- 2 min: 0 max: 10;

    map<int, string> nombres_clave <- [
        15::"Quitumbe", 11::"Recreo", 8::"San Francisco", 6::"UCE", 
        4::"Carolina", 3::"Iñaquito", 1::"Labrador"
    ];

	init {
		// A. Grafos y Limpieza
		red_vial <- as_edge_graph(file_rutas_todas);
		list<geometry> lineas_crudas <- list<geometry>(file_metro.contents);
		list<geometry> lineas_metro_limpias <- clean_network(lineas_crudas, 5.0, true, true);
		red_metro <- as_edge_graph(lineas_metro_limpias);
		geometry geom_metro_unificada <- union(lineas_metro_limpias);

		// B. Crear Estaciones
		create estacion from: file_estaciones { passengers_waiting <- []; }
		
		// Ordenamos las estaciones de Sur (Y menor) a Norte (Y mayor) para saber la dirección
		todas_estaciones <- estacion sort_by (each.location.y);
		
		loop i from: 0 to: length(todas_estaciones) - 1 {
            estacion est <- todas_estaciones[i];
            est.indice_ruta <- i; // Guardamos el orden (0, 1, 2...)
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

		estaciones_sur <- todas_estaciones where (each.nombre_real in ["Quitumbe", "Recreo", "San Francisco", "UCE"]);
		estaciones_norte <- todas_estaciones where (each.nombre_real in ["Carolina", "Iñaquito", "Labrador"]);

		// C. Crear Trenes
		// TRENES SUR (Van hacia el Norte)
		create tren number: 9 {
			location <- estacion_quitumbe.location;
			origen_base <- estacion_quitumbe;
			destino_base <- estacion_labrador;
			direccion_norte <- true; // IMPORTANTE: Define dirección
			estado <- "en_cochera"; 
			passengers_onboard <- [];
			heading <- 90.0;
		}

		// TRENES NORTE (Van hacia el Sur)
		create tren number: 9 {
			location <- estacion_labrador.location;
			origen_base <- estacion_labrador;
			destino_base <- estacion_quitumbe;
			direccion_norte <- false; // IMPORTANTE: Define dirección
			estado <- "en_cochera"; 
			passengers_onboard <- [];
			heading <- 270.0; 
		}
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
		// 1. Generación General
		if (every(tasa_generacion_pasajeros #cycle)) {
			create pasajero {
				estacion origen <- one_of(estacion);
				location <- origen.location; // Nacen en la estación para evitar caminatas largas
				target_station <- origen;
				final_destination <- one_of(estacion - origen);
				// Calculamos direccion: Si indice destino > indice origen, va al Norte
				direccion_norte <- (final_destination.indice_ruta > origen.indice_ruta);
				
				current_belief <- "waiting";
				ask target_station { passengers_waiting << myself; }
			}
		}

		// 2. Generación Específica (Demanda Controlada)
		if (every(20 #cycle)) {
			do inyectar_demanda("Quitumbe", demanda_quitumbe);
			do inyectar_demanda("Recreo", demanda_recreo);
			do inyectar_demanda("San Francisco", demanda_sanfrancisco);
			do inyectar_demanda("UCE", demanda_uce);
			do inyectar_demanda("Carolina", demanda_carolina);
			do inyectar_demanda("Iñaquito", demanda_inaquito);
			do inyectar_demanda("Labrador", demanda_labrador);
		}
	}

	action inyectar_demanda(string nombre_est, int nivel_demanda) {
		if (nivel_demanda > 0) {
			int cantidad <- rnd(0, int(nivel_demanda / 2)); 
			if (cantidad > 0) {
				estacion est <- estacion first_with (each.nombre_real = nombre_est);
				create pasajero number: cantidad {
					location <- est.location;
					target_station <- est;
					final_destination <- one_of(estacion - est);
					// Calculamos direccion
					direccion_norte <- (final_destination.indice_ruta > est.indice_ruta);
					
					current_belief <- "waiting";
					ask target_station { passengers_waiting << myself; }
				}
			}
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
    int indice_ruta; // Indice para saber orden (0=Sur, N=Norte)
    bool es_clave <- false;
    list<pasajero> passengers_waiting;

    aspect base {
        // Cuadrado Amarillo Grande
        int tamano <- es_clave ? 70 : 40;
        rgb color_estacion <- es_clave ? #yellow : #cyan;
        draw square(tamano) color: color_estacion border: #black;

        if (!empty(passengers_waiting)) {
            draw square(tamano + 10) color: #transparent border: #red width: 3;
            draw string(length(passengers_waiting)) at: location + {-10,10} color: #black font: font("Arial", 12, #bold) perspective: false;
        }

        // Etiqueta Botón Blanco
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
	bool direccion_norte; // TRUE = Va al norte, FALSE = Va al sur
	
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
		// 1. Bajada
		list<pasajero> bajar <- passengers_onboard where (each.final_destination = est);
		if (!empty(bajar)) {
			ask bajar { do die; }
			passengers_onboard <- passengers_onboard - bajar;
		}

		// 2. Subida (CORREGIDO: FILTRO DE DIRECCIÓN)
		int ocupados <- length(passengers_onboard);
		int cupo <- capacidad_total_tren - ocupados;
		
		if (cupo > 0 and !empty(est.passengers_waiting)) {
			// TRUCO: Guardamos la dirección del tren en una variable local
			bool mi_direccion <- direccion_norte;
			
			// Filtramos: Solo suben los que van en la MISMA dirección que el tren
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
	bool direccion_norte; // Define si quiere ir al norte o sur
	string current_belief <- "walking_to_station";

	reflex walk when: current_belief = "walking_to_station" {
		// Pasajeros ya nacen en la estación para esta versión, pero mantenemos por si acaso
		if (location distance_to target_station < 30) {
			current_belief <- "waiting";
			ask target_station { passengers_waiting << myself; }
		}
	}
	reflex ride when: current_belief = "on_train" { }
	aspect base { 
		if (current_belief = "waiting") { 
			// Azul si va al norte, Naranja si va al Sur
			draw circle(8) color: direccion_norte ? #blue : #orange; 
		} 
	}
}

experiment Visualizacion type: gui {
	// --- SLIDERS ORIGINALES ---
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Configuracion Tren" min: 20.0 max: 120.0;
    parameter "Numero Vagones" var: numero_vagones category: "Configuracion Tren" min: 1 max: 12; 
    parameter "Intervalo Salida (min)" var: intervalo_despacho_minutos category: "Configuracion Tren" min: 1.0 max: 20.0;
    parameter "Tasa Llegada General" var: tasa_generacion_pasajeros category: "Configuracion Pasajeros" min: 1 max: 50; 
    parameter "Velocidad Simulacion" var: factor_velocidad category: "Sistema" min: 0.1 max: 20.0;

    // --- NUEVOS SLIDERS (DEMANDA) ---
    parameter "Demanda Quitumbe" var: demanda_quitumbe category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Recreo" var: demanda_recreo category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda San Francisco" var: demanda_sanfrancisco category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda UCE" var: demanda_uce category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Carolina" var: demanda_carolina category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Iñaquito" var: demanda_inaquito category: "Control Demanda Estaciones" min: 0 max: 10;
    parameter "Demanda Labrador" var: demanda_labrador category: "Control Demanda Estaciones" min: 0 max: 10;

	output {
		layout #split;
		display mapa type: opengl background: #gray {
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
			
		}
		display "Estadisticas" {
			chart "Pasajeros" type: series {
				data "Esperando" value: sum(estacion collect length(each.passengers_waiting)) color: #blue;
				data "En Tren" value: sum(tren collect length(each.passengers_onboard)) color: #green;
			}
		}
	}
}