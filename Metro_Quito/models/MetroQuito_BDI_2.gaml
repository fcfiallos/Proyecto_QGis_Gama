/**
* Name: MetroQuito_Final
* Description: Simulacion completa con horarios, flujo direccional y visualizacion corregida.
*/

model MetroQuitoBDI2

global {
	// --- 1. CONFIGURACIÓN ---
	float step <- 1 #s; 
	// Iniciamos a las 5:50 AM para ver el primer despacho a las 6:00
	date starting_date <- date("2023-11-01 05:50:00");

	// --- 2. CARGA DE ARCHIVOS ---
	file file_edificios <- file("../includes/edificios.shp");
	file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
	// Archivos adicionales solicitados
	file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");	
	file file_principales <- file("../includes/principales.shp");
	file file_secundarias <- file("../includes/secundarias.shp");
	
	file file_metro <- file("../includes/ruta_metro.shp");
	
	// IMAGEN: Definida explícitamente como image_file
	image_file icono_tren <- image_file("../includes/tren_metro.png");

	geometry shape <- envelope(file_edificios);

	// --- 3. VARIABLES GLOBALES ---
	graph red_vial;
	graph red_metro;
	
	list<geometry> lista_edificios <- file_edificios.contents;
	list<geometry> lista_principales <- file_principales.contents;
	list<geometry> lista_secundarias <- file_secundarias.contents;
	list<geometry> formas_metro <- file_metro.contents;

	// Listas lógicas de estaciones
	estacion estacion_quitumbe;
	estacion estacion_labrador;
	list<estacion> estaciones_sur; // Para hora pico mañana (origen)
	list<estacion> estaciones_norte; // Para hora pico mañana (destino)
	
	// Datos de configuración
	int total_trenes <- 18;
	int capacidad_total_tren <- 1230;

	// Variables de control de despacho
	float tiempo_ultimo_despacho <- -9999.0;
	
	// Variables dinámicas controladas por sliders (definidas aquí con valores base)
	float velocidad_tren_kmh <- 60.0;
    float factor_velocidad <- 1.0;
	float velocidad_tren -> (velocidad_tren_kmh #km/#h) * factor_velocidad;
	float velocidad_pasajero <- 5.0 #km / #h;

	// Mapeo de Nombres (Copiado de tu código anterior)
    map<int, string> nombres_clave <- [
        15::"Quitumbe", 11::"Recreo", 8::"San Francisco", 6::"UCE", 
        4::"Carolina", 3::"Iñaquito", 1::"Labrador"
    ];

	init {
		// A. Grafos
		red_vial <- as_edge_graph(file_rutas_todas);
		// Importante: Aseguramos que el grafo del metro sea undirected para facilitar ida/vuelta si las lineas están conectadas
		red_metro <- as_edge_graph(file_metro);

		// B. Crear Estaciones y asignar Nombres
		create estacion from: file_estaciones {
			passengers_waiting <- [];
		}
		
		// Ordenar de Sur (Y menor) a Norte (Y mayor) para asignar IDs visuales
		list<estacion> estaciones_ordenadas <- estacion sort_by (each.location.y);
		
		loop i from: 0 to: length(estaciones_ordenadas) - 1 {
            estacion est <- estaciones_ordenadas[i];
            est.id_visual <- i + 1; 
            
            if (nombres_clave contains_key (est.id_visual)) {
                est.nombre_real <- nombres_clave[est.id_visual];
                est.es_clave <- true;
            } else {
                est.nombre_real <- "E-" + string(est.id_visual);
            }
        }
        
        // Identificar grupos para la lógica de horas pico
        estacion_quitumbe <- estaciones_ordenadas first_with (each.nombre_real = "Quitumbe");
        estacion_labrador <- estaciones_ordenadas first_with (each.nombre_real = "Labrador");
        
        // Si no encuentra por nombre (por si el shapefile es distinto), usa extremos
        if (estacion_quitumbe = nil) { estacion_quitumbe <- first(estaciones_ordenadas); }
        if (estacion_labrador = nil) { estacion_labrador <- last(estaciones_ordenadas); }

		// Llenar listas Sur y Norte basándonos en los nombres clave o posición
		estaciones_sur <- estaciones_ordenadas where (each.nombre_real in ["Quitumbe", "Recreo", "San Francisco", "UCE"]);
		estaciones_norte <- estaciones_ordenadas where (each.nombre_real in ["Carolina", "Iñaquito", "Labrador"]);

		// C. Crear Trenes en Quitumbe (Reposo)
		create tren number: total_trenes {
			// Ubicar en Quitumbe pero asegurando que esté EN el grafo
			location <- estacion_quitumbe.location;
			estado <- "reposo"; 
			passengers_onboard <- [];
		}
	}

	// --- LOGICA DE DESPACHO DE TRENES ---
	reflex sistema_despacho {
		float intervalo_despacho <- 480.0; // 8 min default
		bool es_pico <- (current_date.hour >= 6 and current_date.hour < 10) or (current_date.hour >= 17 and current_date.hour < 20);
		
		if (es_pico) { intervalo_despacho <- 300.0; } // 5 min pico

		if ((time - tiempo_ultimo_despacho) >= intervalo_despacho) {
			tren t <- first(tren where (each.estado = "reposo"));
			if (t != nil) {
				ask t {
					estado <- "ida";
					target_station <- estacion_labrador;
					// Calcular ruta. Usamos red_metro.
					camino_actual <- path_between(red_metro, estacion_quitumbe, estacion_labrador);
				}
				tiempo_ultimo_despacho <- time;
			}
		}
	}

	// --- GENERADOR INTELIGENTE DE PASAJEROS ---
	reflex generar_pasajeros {
		// Tasa de aparición: Muy alta en pico (cada 2 ciclos), baja en valle (cada 10)
		bool es_pico_manana <- (current_date.hour >= 6 and current_date.hour < 10);
		bool es_pico_tarde <- (current_date.hour >= 17 and current_date.hour < 20);
		int tasa <- (es_pico_manana or es_pico_tarde) ? 2 : 10; 
		
		if (every(tasa #cycle)) {
			estacion origen <- nil;
			estacion destino <- nil;

			if (es_pico_manana) {
				// Mañana: Sur -> Norte
				origen <- empty(estaciones_sur) ? one_of(estacion) : one_of(estaciones_sur);
				destino <- empty(estaciones_norte) ? one_of(estacion) : one_of(estaciones_norte);
			} else if (es_pico_tarde) {
				// Tarde: Norte -> Sur
				origen <- empty(estaciones_norte) ? one_of(estacion) : one_of(estaciones_norte);
				destino <- empty(estaciones_sur) ? one_of(estacion) : one_of(estaciones_sur);
			} else {
				// Valle: Random
				origen <- one_of(estacion);
				destino <- one_of(estacion - origen);
			}

			create pasajero {
				location <- any_location_in(origen.location + 50); // Aparecen cerca
				target_station <- origen;
				final_destination <- destino;
			}
		}
	}
}

// --- GRID (Fuera de Global) ---
grid mapa_densidad width: 60 height: 60 {
    int pax_count <- 0 update: length(pasajero inside self);
    float intensidad <- 0.0 update: (pax_count / 50.0);
    // Corrección sintaxis: ternario y blend verde->rojo
    rgb color <- #transparent update: (pax_count = 0) ? #transparent : blend(#green, #red, (intensidad > 1.0 ? 1.0 : intensidad));
}

// --- ESPECIES ---

species estacion {
	string nombre_real;
	int id_visual;
	bool es_clave <- false;
	list<pasajero> passengers_waiting;

	aspect base {
		// Puntos azules, más grandes si son clave
		draw circle(es_clave ? 40 : 20) color: #blue border: #white;
		
		// Indicador de congestión (borde rojo si hay gente)
		if (!empty(passengers_waiting)) {
			draw circle(es_clave ? 45 : 25) color: #transparent border: #red width: 2;
		}

		if (es_clave) {
			draw nombre_real color: #black font: font("Arial", 16, #bold) at: location + {20, 20} perspective: false;
		}
	}
}

species tren skills: [moving] {
	string estado; // "reposo", "ida", "vuelta"
	list<pasajero> passengers_onboard;
	estacion target_station;
	path camino_actual;

	reflex movimiento when: estado != "reposo" {
		// Moverse
		do follow path: camino_actual speed: velocidad_tren;
		
		// Actualizar ubicación de pasajeros a bordo (para que no se queden flotando)
		if (!empty(passengers_onboard)) {
			ask passengers_onboard { location <- myself.location; }
		}

		// Detectar parada (radio ampliado a 50m)
		estacion est <- estacion closest_to self;
		if (self distance_to est < 50) {
			do gestionar_pasajeros(est);
		}

		// Fin de ruta
		if (location distance_to target_station < 50) {
			if (estado = "ida") {
				estado <- "vuelta";
				target_station <- estacion_quitumbe;
				camino_actual <- path_between(red_metro, estacion_labrador, estacion_quitumbe);
			} else {
				estado <- "reposo";
				camino_actual <- nil;
				// Descargar a todos
				ask passengers_onboard { do die; }
				passengers_onboard <- [];
			}
		}
	}

	action gestionar_pasajeros (estacion est) {
		// 1. Bajar
		list<pasajero> bajar <- passengers_onboard where (each.final_destination = est);
		if (!empty(bajar)) {
			ask bajar { do die; }
			passengers_onboard <- passengers_onboard - bajar;
		}

		// 2. Subir
		int cupo <- capacidad_total_tren - length(passengers_onboard);
		if (cupo > 0 and !empty(est.passengers_waiting)) {
			int n <- min([cupo, length(est.passengers_waiting)]);
			list<pasajero> suben <- est.passengers_waiting copy_between(0, n);
			
			ask suben {
				myself.passengers_onboard << self;
				current_belief <- "on_train";
				location <- myself.location; // CRUCIAL: Moverlos al tren inmediatamente
			}
			est.passengers_waiting <- est.passengers_waiting - suben;
		}
	}

	aspect base {
		if (estado != "reposo") {
			// Dibuja la imagen si existe, sino un rectángulo grande
			if (file_exists("../includes/tren_metro.png")) {
				// Tamaño aumentado a 150 para que se vea bien en el mapa
				draw icono_tren size: 150 rotate: heading + 90; 
			} else {
				draw rectangle(150, 40) color: #white border: #red rotate: heading;
				draw "METRO" color: #red size: 20 rotate: heading at: location;
			}
			// Texto de capacidad
			draw string(length(passengers_onboard)) + "/" + string(capacidad_total_tren) color: #black size: 20 at: location + {0,50} perspective: false;
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
	
	reflex ride when: current_belief = "on_train" {
		// La posición la actualiza el tren
	}

	aspect base {
		if (current_belief = "walking_to_station") {
			draw circle(8) color: #cyan;
		}
		// Si está esperando o en tren, no se dibuja (lo maneja la estación/tren/mapa calor)
	}
}

// --- EXPERIMENTO ---
experiment Visualizacion type: gui {
	// Parámetros AQUÍ (Correcto)
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Control" min: 20.0 max: 120.0;
    parameter "Velocidad Simulación" var: factor_velocidad category: "Control" min: 0.1 max: 20.0;

	output {
		layout #split;
		
		display mapa type: opengl background: #gray {
			// 1. Mapa de Calor (Fondo)
			grid mapa_densidad transparency: 0.5;

			// 2. Infraestructura Estática
			graphics "Vias" {
				
				// Edificios
				loop g over: lista_edificios { draw g color: #darkgray wireframe: true; }
				// Principales (Naranja)
				loop g over: lista_principales { draw g color: #orange width: 2; }
				// Secundarias (Violeta)
				loop g over: lista_secundarias { draw g color: #violet; }
				// Metro (Blanco borde Rojo)
				loop g over: formas_metro { 
					 //draw g + 10 color: #red; Borde (truco visual: linea mas ancha atras)
					draw g color: #white; //width: 3 
				}
			}

			// 3. Agentes Dinámicos
			species estacion aspect: base;
			species tren aspect: base;
			species pasajero aspect: base;
			

			// 4. Panel de Información (HUD)
			graphics "HUD" {
				draw "Hora: " + string(current_date.hour) + ":" + (current_date.minute < 10 ? "0" : "") + string(current_date.minute) 
					at: {50, 100} color: #white font: font("Arial", 24, #bold) perspective: false;
				
				bool es_pico <- (current_date.hour >= 6 and current_date.hour < 10) or (current_date.hour >= 17 and current_date.hour < 20);
				string estado_txt <- es_pico ? "HORA PICO (Despacho 5min)" : "HORA VALLE (Despacho 8min)";
				rgb color_txt <- es_pico ? #red : #green;
				
				draw estado_txt at: {50, 200} color: color_txt font: font("Arial", 18) perspective: false;
			}
		}

		display "Estadisticas" {
			chart "Pasajeros" type: series {
				data "Esperando en Estación" value: sum(estacion collect length(each.passengers_waiting)) color: #blue;
				data "Viajando en Tren" value: sum(tren collect length(each.passengers_onboard)) color: #green;
			}
		}
	}
}