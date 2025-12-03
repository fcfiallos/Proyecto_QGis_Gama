/**
* Name: MetroQuito_Final_Corregido
* Description: Simulacion con trenes moviendose, flujo bidireccional y correccion de grafos.
*/

model MetroQuitoBDI2

global {
	// --- 1. CONFIGURACIÓN ---
	float step <- 1 #s; 
	date starting_date <- date("2023-11-01 05:50:00");

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
	
	int total_trenes <- 18;
	int capacidad_total_tren <- 1230;

	// Variables de control de despacho
	float tiempo_ultimo_despacho <- -9999.0;
	
	float velocidad_tren_kmh <- 80.0; // Subí un poco la velocidad base
    float factor_velocidad <- 1.0;
	float velocidad_tren -> (velocidad_tren_kmh #km/#h) * factor_velocidad;
	float velocidad_pasajero <- 5.0 #km / #h;

    map<int, string> nombres_clave <- [
        15::"Quitumbe", 11::"Recreo", 8::"San Francisco", 6::"UCE", 
        4::"Carolina", 3::"Iñaquito", 1::"Labrador"
    ];

	init {
		// A. Grafos y Limpieza
		red_vial <- as_edge_graph(file_rutas_todas);
		
		// 1. Convertimos a lista para clean_network
		list<geometry> lineas_crudas <- list<geometry>(file_metro.contents);
		
		// 2. Limpiamos huecos (tolerancia 5m) y unimos líneas
		list<geometry> lineas_metro_limpias <- clean_network(lineas_crudas, 5.0, true, true);
		
		// 3. Creamos el grafo
		red_metro <- as_edge_graph(lineas_metro_limpias);

		// 4. Geometría unificada para usar de imán
		geometry geom_metro_unificada <- union(lineas_metro_limpias);

		// B. Crear Estaciones
		create estacion from: file_estaciones {
			passengers_waiting <- [];
		}
		
		// Ordenar estaciones
		list<estacion> estaciones_ordenadas <- estacion sort_by (each.location.y);
		
		loop i from: 0 to: length(estaciones_ordenadas) - 1 {
            estacion est <- estaciones_ordenadas[i];
            est.id_visual <- i + 1; 
            
            // Asignar nombres
            if (nombres_clave contains_key (est.id_visual)) {
                est.nombre_real <- nombres_clave[est.id_visual];
                est.es_clave <- true;
            } else {
                est.nombre_real <- "E-" + string(est.id_visual);
            }
            
            // /// CORRECCIÓN DEFINITIVA: SNAPPING ///
            // closest_points_with devuelve una lista de 2 puntos: [punto_en_metro, punto_en_estacion]
            // Tomamos el primero ([0]) que es el punto exacto sobre el riel.
            est.location <- (geom_metro_unificada closest_points_with est.location)[0];
        }
        
        // Identificar extremos
        estacion_quitumbe <- estaciones_ordenadas first_with (each.nombre_real = "Quitumbe");
        estacion_labrador <- estaciones_ordenadas first_with (each.nombre_real = "Labrador");
        
        if (estacion_quitumbe = nil) { estacion_quitumbe <- first(estaciones_ordenadas); }
        if (estacion_labrador = nil) { estacion_labrador <- last(estaciones_ordenadas); }

		// Listas lógicas
		estaciones_sur <- estaciones_ordenadas where (each.nombre_real in ["Quitumbe", "Recreo", "San Francisco", "UCE"]);
		estaciones_norte <- estaciones_ordenadas where (each.nombre_real in ["Carolina", "Iñaquito", "Labrador"]);

		// C. Crear Trenes (Distribuidos 9 y 9)
		
		// Trenes en Quitumbe (Sur)
		create tren number: 9 {
			location <- estacion_quitumbe.location;
			origen_base <- estacion_quitumbe;
			destino_base <- estacion_labrador;
			estado <- "en_cochera"; 
			passengers_onboard <- [];
			heading <- 90.0;
		}

		// Trenes en Labrador (Norte)
		create tren number: 9 {
			location <- estacion_labrador.location;
			origen_base <- estacion_labrador;
			destino_base <- estacion_quitumbe;
			estado <- "en_cochera"; 
			passengers_onboard <- [];
			heading <- 270.0; 
		}
	}
	
	
	// --- LOGICA DE DESPACHO DE TRENES ---
	reflex sistema_despacho {
		float intervalo_despacho <- 480.0; // 8 min default
		bool es_pico <- (current_date.hour >= 6 and current_date.hour < 10) or (current_date.hour >= 17 and current_date.hour < 20);
		
		if (es_pico) { intervalo_despacho <- 300.0; } // 5 min pico

		if ((time - tiempo_ultimo_despacho) >= intervalo_despacho) {
			
			// /// CORRECCIÓN 4: DESPACHO DOBLE ///
			// Intentamos despachar uno del sur y uno del norte simultáneamente
			
			// 1. Despachar desde Quitumbe (Sur -> Norte)
			tren t_sur <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_quitumbe));
			if (t_sur != nil) {
				ask t_sur {
					do iniciar_viaje(estacion_labrador);
				}
			}
			
			// 2. Despachar desde Labrador (Norte -> Sur)
			tren t_norte <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_labrador));
			if (t_norte != nil) {
				ask t_norte {
					do iniciar_viaje(estacion_quitumbe);
				}
			}

			// Actualizamos tiempo solo si al menos uno salió (o forzamos el ciclo)
			tiempo_ultimo_despacho <- time;
		}
	}

	reflex generar_pasajeros {
		bool es_pico_manana <- (current_date.hour >= 6 and current_date.hour < 10);
		bool es_pico_tarde <- (current_date.hour >= 17 and current_date.hour < 20);
		int tasa <- (es_pico_manana or es_pico_tarde) ? 2 : 10; 
		
		if (every(tasa #cycle)) {
			estacion origen <- nil;
			estacion destino <- nil;

			if (es_pico_manana) {
				origen <- empty(estaciones_sur) ? one_of(estacion) : one_of(estaciones_sur);
				destino <- empty(estaciones_norte) ? one_of(estacion) : one_of(estaciones_norte);
			} else if (es_pico_tarde) {
				origen <- empty(estaciones_norte) ? one_of(estacion) : one_of(estaciones_norte);
				destino <- empty(estaciones_sur) ? one_of(estacion) : one_of(estaciones_sur);
			} else {
				origen <- one_of(estacion);
				destino <- one_of(estacion - origen);
			}

			create pasajero {
				location <- any_location_in(origen.location + 50); 
				target_station <- origen;
				final_destination <- destino;
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
	bool es_clave <- false;
	list<pasajero> passengers_waiting;

	aspect base {
		draw circle(es_clave ? 40 : 20) color: #blue border: #white;
		if (!empty(passengers_waiting)) {
			draw circle(es_clave ? 45 : 25) color: #transparent border: #red width: 2;
		}
		if (es_clave) {
			draw nombre_real color: #black font: font("Arial", 16, #bold) at: location + {20, 20} perspective: false;
		}
	}
}


species tren skills: [moving] {
	string estado; // "en_cochera", "movimiento"
	estacion origen_base;
	estacion destino_base;
	
	estacion target_station; 
	path camino_actual;
	list<pasajero> passengers_onboard;
	
	// Variables para el texto dinámico
	string ruta_display <- "";
	rgb color_texto <- #blue; // Color por defecto

	// Acción para iniciar ruta y actualizar el texto
	action iniciar_viaje (estacion destino_objetivo) {
		estado <- "movimiento";
		target_station <- destino_objetivo;
		
		// Calculamos el camino
		camino_actual <- path_between(red_metro, location, target_station.location);
		
		// --- LÓGICA DE TEXTO Y COLOR CORTO ---
		if (destino_objetivo.nombre_real = "Labrador") {
			// Ida: Quitumbe a Labrador (Q >> L) -> AZUL
			ruta_display <- "Q >> L";
			color_texto <- #blue;
		} else {
			// Vuelta: Labrador a Quitumbe (L >> Q) -> NARANJA
			ruta_display <- "L >> Q";
			color_texto <- #orange;
		}

		if (camino_actual = nil) {
			write "ERROR: Ruta no encontrada";
			estado <- "en_cochera";
		}
	}

	reflex movimiento when: estado = "movimiento" {
		if (camino_actual != nil) {
			do follow path: camino_actual speed: velocidad_tren;
		}
		
		if (!empty(passengers_onboard)) {
			ask passengers_onboard { location <- myself.location; }
		}

		// Detectar parada
		estacion est <- estacion closest_to self;
		if (self distance_to est < 60) { 
			do gestionar_pasajeros(est);
		}

		// Llegada al destino
		if (location distance_to target_station < 60) {
			if (target_station = destino_base) {
				// Llegó al final, da la vuelta inmediatamente
				do iniciar_viaje(origen_base);
			} else {
				// Llegó a casa, termina turno
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

		int cupo <- capacidad_total_tren - length(passengers_onboard);
		if (cupo > 0 and !empty(est.passengers_waiting)) {
			int n <- min([cupo, length(est.passengers_waiting)]);
			list<pasajero> suben <- est.passengers_waiting copy_between(0, n);
			
			ask suben {
				myself.passengers_onboard << self;
				current_belief <- "on_train";
				location <- myself.location; 
			}
			est.passengers_waiting <- est.passengers_waiting - suben;
		}
	}

	aspect base {
		if (estado != "en_cochera") {
			// --- DIBUJO DE VAGONES ---
			rgb color_vagon <- #white;
			rgb color_borde <- #red; // Borde rojo siempre (identidad Metro Quito)
			
			float largo_vagon <- 50.0;
			float ancho_vagon <- 15.0;
			float separacion <- 52.0; 
			point vector_dir <- {cos(heading), sin(heading)};
			
			// 1. Vagón Central
			draw rectangle(largo_vagon, ancho_vagon) color: color_vagon border: color_borde rotate: heading;
			
			// 2. Vagón Delantero
			draw rectangle(largo_vagon, ancho_vagon) color: color_vagon border: color_borde rotate: heading at: location + (vector_dir * separacion);
			// Triángulo indicador dirección
			draw polygon([location + (vector_dir * (separacion + 20)), location + (vector_dir * (separacion + 25)) + {cos(heading+90)*7, sin(heading+90)*7}, location + (vector_dir * (separacion + 25)) - {cos(heading+90)*7, sin(heading+90)*7}]) color: #red border: #red;

			// 3. Vagón Trasero
			draw rectangle(largo_vagon, ancho_vagon) color: color_vagon border: color_borde rotate: heading at: location - (vector_dir * separacion);
			
			// Acoples
			draw line([location, location + (vector_dir * separacion)]) color: #black width: 2;
			draw line([location, location - (vector_dir * separacion)]) color: #black width: 2;

			// --- TEXTO CORTO Y COLOREADO ---
			draw ruta_display 
				at: location + {30, 30} 
				color: color_texto // Usa la variable dinámica (Azul o Naranja)
				font: font("Arial", 20, #bold) 
				perspective: false; // Siempre mira al frente
				
		} else {
			draw circle(10) color: #darkgray at: location;
		}
	}
}

species pasajero skills: [moving] control: simple_bdi {
	estacion target_station;
	estacion final_destination;
	string current_belief <- "walking_to_station";

	reflex walk when: current_belief = "walking_to_station" {
		do goto target: target_station on: red_vial speed: velocidad_pasajero;
		if (location distance_to target_station < 30) {
			current_belief <- "waiting";
			ask target_station { passengers_waiting << myself; }
		}
	}
	
	reflex ride when: current_belief = "on_train" { }

	aspect base {
		if (current_belief = "walking_to_station") {
			draw circle(8) color: #cyan;
		}
	}
}

experiment Visualizacion type: gui {
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Control" min: 20.0 max: 120.0;
    parameter "Velocidad Simulación" var: factor_velocidad category: "Control" min: 0.1 max: 20.0;

	output {
		layout #split;
		display mapa type: opengl background: #gray {
			grid mapa_densidad transparency: 0.5;
			graphics "Vias" {
				loop g over: lista_edificios { draw g color: #darkgray wireframe: true; }
				loop g over: lista_principales { draw g color: #orange width: 2; }
				loop g over: lista_secundarias { draw g color: #violet; }
				loop g over: formas_metro { draw g color: #white; }
			}
			species estacion aspect: base;
			species tren aspect: base;
			species pasajero aspect: base;
			
			graphics "HUD" {
				draw "Hora: " + string(current_date.hour) + ":" + (current_date.minute < 10 ? "0" : "") + string(current_date.minute) 
					at: {50, 100} color: #white font: font("Arial", 24, #bold) perspective: false;
				bool es_pico <- (current_date.hour >= 6 and current_date.hour < 10) or (current_date.hour >= 17 and current_date.hour < 20);
				draw es_pico ? "HORA PICO" : "HORA VALLE" at: {50, 200} color: es_pico ? #red : #green font: font("Arial", 18) perspective: false;
			}
		}
		display "Estadisticas" {
			chart "Pasajeros" type: series {
				data "Esperando" value: sum(estacion collect length(each.passengers_waiting)) color: #blue;
				data "En Tren" value: sum(tren collect length(each.passengers_onboard)) color: #green;
			}
		}
	}
}