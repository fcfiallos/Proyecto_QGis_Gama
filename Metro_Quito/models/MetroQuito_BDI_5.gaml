/**
* Name: MetroQuito_Final_Interactivo
* Description: Simulacion con controles interactivos (sliders) para vagones, pasajeros y tiempos.
*/

model MetroQuitoBDI2

global {
	// --- 1. CONFIGURACIÓN BÁSICA ---
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
	
	// --- VARIABLES DE INTERFAZ (SLIDERS) ---
	float velocidad_tren_kmh <- 80.0; 
    float factor_velocidad <- 1.0;
	float velocidad_tren -> (velocidad_tren_kmh #km/#h) * factor_velocidad;
	float velocidad_pasajero <- 5.0 #km / #h;
	
	// NUEVOS PARAMETROS CONFIGURABLES
	int numero_vagones <- 3 min: 1 max: 6; // Controla el dibujo
	int tasa_generacion_pasajeros <- 5 min: 1 max: 50; // Menor numero = Mas rapido (cada N ciclos)
	float intervalo_despacho_minutos <- 5.0 min: 1.0 max: 20.0; // Tiempo entre trenes

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
            
            // SNAPPING
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
		create tren number: 9 {
			location <- estacion_quitumbe.location;
			origen_base <- estacion_quitumbe;
			destino_base <- estacion_labrador;
			estado <- "en_cochera"; 
			passengers_onboard <- [];
			heading <- 90.0;
		}

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
		// Usamos el slider para controlar el intervalo
		float intervalo_segundos <- intervalo_despacho_minutos * 60; 

		if ((time - tiempo_ultimo_despacho) >= intervalo_segundos) {
			
			// 1. Despachar desde Quitumbe
			tren t_sur <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_quitumbe));
			if (t_sur != nil) {
				ask t_sur { do iniciar_viaje(estacion_labrador); }
			}
			
			// 2. Despachar desde Labrador
			tren t_norte <- first(tren where (each.estado = "en_cochera" and each.origen_base = estacion_labrador));
			if (t_norte != nil) {
				ask t_norte { do iniciar_viaje(estacion_quitumbe); }
			}

			tiempo_ultimo_despacho <- time;
		}
	}

	reflex generar_pasajeros {
		// Usamos el slider para la tasa (mas bajo = mas rapido)
		if (every(tasa_generacion_pasajeros #cycle)) {
			estacion origen <- nil;
			estacion destino <- nil;
			
			// Lógica simplificada de hora pico para no complicar el slider
			bool es_pico_manana <- (current_date.hour >= 6 and current_date.hour < 10);
			bool es_pico_tarde <- (current_date.hour >= 17 and current_date.hour < 20);

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
        // 1. CUADRADOS MUCHO MÁS GRANDES
        // Clave: 80 px (antes era 45) | Normales: 50 px
        int tamano <- es_clave ? 180 : 50;
        rgb color_estacion <- es_clave ? #yellow : #cyan;
        
        // Dibujamos el cuadrado
        draw square(tamano) color: color_estacion border: #black;

        if (!empty(passengers_waiting)) {
            draw square(tamano + 10) color: #transparent border: #red width: 3;
        }

        // 2. LA ETIQUETA "BOTÓN" (CORREGIDA Y ELEVADA)
        if (es_clave) {
            // Posición: A la derecha del cuadrado (+80px) y ELEVADA 5 metros (+ {0,0,5})
            // El {0,0,5} es vital para que el mapa gris no se "coma" al botón blanco.
            point pos_etiqueta <- location + {80, 0, 5}; 
            
            // Calculamos el ancho basado en el largo del nombre
            float ancho_boton <- (length(nombre_real) * 14.0) + 20;
            float alto_boton <- 40.0;

            // A. DIBUJAR EL FONDO BLANCO (RECTÁNGULO)
            draw rectangle(ancho_boton, alto_boton) 
                at: pos_etiqueta
                color: #white 
                border: #black; 

            // B. DIBUJAR EL TEXTO NEGRO
            // Lo dibujamos en la misma posición (encima del rectángulo)
            draw nombre_real 
                at: pos_etiqueta 
                color: #black 
                font: font("Arial", 16, #bold) 
                anchor: #center; // Centrado en el rectángulo
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
	
	string ruta_display <- "";
	rgb color_texto <- #blue;

	action iniciar_viaje (estacion destino_objetivo) {
		estado <- "movimiento";
		target_station <- destino_objetivo;
		camino_actual <- path_between(red_metro, location, target_station.location);
		
		if (destino_objetivo.nombre_real = "Labrador") {
			ruta_display <- "Q >> L";
			color_texto <- #blue;
		} else {
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

		estacion est <- estacion closest_to self;
		if (self distance_to est < 60) { 
			do gestionar_pasajeros(est);
		}

		if (location distance_to target_station < 60) {
			if (target_station = destino_base) {
				do iniciar_viaje(origen_base);
			} else {
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
			// --- DIBUJO DINÁMICO DE VAGONES (CORREGIDO) ---
			rgb color_vagon <- #white;
			rgb color_borde <- #red;
			float largo_vagon <- 50.0;
			float ancho_vagon <- 15.0;
			float separacion <- 52.0; 
			point vector_dir <- {cos(heading), sin(heading)};
			
			// Cálculo del desplazamiento inicial
			float offset_inicial <- -1 * ((numero_vagones - 1) * separacion) / 2.0;

			// Bucle simplificado
			loop i from: 0 to: numero_vagones - 1 {
				float mi_offset <- offset_inicial + (i * separacion);
				point pos_vagon <- location + (vector_dir * mi_offset);
				
				// Dibujar vagón
				draw rectangle(largo_vagon, ancho_vagon) color: color_vagon border: color_borde rotate: heading at: pos_vagon;
				
				// Cabeza del tren (Simplificado para evitar errores de paréntesis)
				if (i = (numero_vagones - 1)) {
					// Calculamos los puntos antes de dibujar para que GAMA no se confunda
					point punta_flecha <- pos_vagon + (vector_dir * 25);
					
					// Vector perpendicular para el ancho de la flecha
					float dx_perp <- cos(heading + 90) * 7;
					float dy_perp <- sin(heading + 90) * 7;
					point lado1 <- punta_flecha + {dx_perp, dy_perp};
					point lado2 <- punta_flecha - {dx_perp, dy_perp};
					
					point base_flecha <- pos_vagon + (vector_dir * 20);
					
					draw polygon([base_flecha, lado1, lado2]) color: #red border: #red;
				}
			}

			// Texto informativo
			draw ruta_display 
				at: location + {30, 30} 
				color: color_texto
				font: font("Arial", 20, #bold) 
				perspective: false;
				
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
	// --- AQUI ESTÁN TUS BOTONES DE "VOLUMEN" (SLIDERS) ---
	
	// Categoria Tren
    parameter "Velocidad Tren (km/h)" var: velocidad_tren_kmh category: "Configuracion Tren" min: 20.0 max: 120.0;
    parameter "Numero Vagones" var: numero_vagones category: "Configuracion Tren" min: 1 max: 6;
    parameter "Intervalo Salida (min)" var: intervalo_despacho_minutos category: "Configuracion Tren" min: 1.0 max: 20.0;
    
    // Categoria Pasajeros
    parameter "Tasa Llegada Pasajeros" var: tasa_generacion_pasajeros category: "Configuracion Pasajeros" min: 1 max: 30; // 1 = Muy rapido, 30 = Lento
    parameter "Velocidad Simulacion" var: factor_velocidad category: "Sistema" min: 0.1 max: 20.0;

	output {
		layout #split;
		
		// 1. FONDO GRIS (Mejor contraste para el blanco)
		display mapa type: opengl background: #gray {
			
			grid mapa_densidad transparency: 0.6;
			
			graphics "Vias" {
				// Edificios: Gris oscuro sutil (solo contorno)
				loop g over: lista_edificios { draw g color: #darkgray wireframe: true; }
				
				// VIAS PRINCIPALES (Pastel Naranja Suave)
				// Se ven, pero no molestan.
				loop g over: lista_principales { draw g color: rgb(255, 200, 120) width: 2; }
				
				// VIAS SECUNDARIAS (Pastel Azul/Lila Grisáceo)
				// Dan textura sin hacer ruido visual.
				loop g over: lista_secundarias { draw g color: rgb(170, 170, 190); }
				
				// --- EL METRO (EL REY DEL MAPA) ---
				// Blanco puro y MUY grueso (width: 8) para que sea la base de los trenes
				loop g over: formas_metro { draw g color: #white width: 5; } 
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