/**
* Name: MetroQuitoBDI
* Based on the internal empty template. 
* Author: fcaro
* Tags: 
*/
model MetroQuito_BDI

global {
// --- 1. CARGA DE ARCHIVOS ---
 file file_edificios <- file("../includes/edificios.shp");
	file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
	file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");
	file file_principales <- file("../includes/principales.shp");
	file file_secundarias <- file("../includes/secundarias.shp");
	file file_metro <- file("../includes/ruta_metro.shp");
	geometry shape <- envelope(file_edificios);
	// --- 2. LISTAS DE GEOMETRÍA (Para optimizar visualización) ---
 // Al guardarlas aquí, GAMA ya sabe que son de tipo <geometry>
 list<geometry>
	lista_edificios <- file_edificios.contents;
	list<geometry> formas_rutas <- file_rutas_todas.contents;
	list<geometry> lista_principales <- file_principales.contents;
	list<geometry> lista_secundarias <- file_secundarias.contents;
	list<geometry> formas_metro <- file_metro.contents;

	// --- 3. VARIABLES GLOBALES ---
 graph red_vial;
	graph red_metro;
	// Lista de estaciones clave para simulación
    list<estacion> estaciones_clave; 

    // Mapeo de IDs según tu imagen (Asegúrate que el orden geográfico coincida)
    // Asumiendo orden Sur -> Norte (Quitumbe es Y menor, Labrador es Y mayor)
    map<int, string> nombres_clave <- [
        15::"Quitumbe", 
        11::"Recreo", 
        8::"San Francisco", 
        6::"UCE", 
        4::"Carolina", 
        1::"Labrador"
    ];

	// Parámetros
 int capacidad_tren <- 1200;
	float velocidad_pasajero <- 5.0 #km / #h;
	float velocidad_tren <- 60.0 #km / #h;
	int intervalo_llegada_pasajeros <- 50;

	// Umbrales para visualización de cuellos de botella
 int umbral_amarillo <- 20;
	int umbral_rojo <- 100;

	init {
	// A. Crear la red vial para caminar (unificando las líneas)
 // Crear grafos para movimiento
 red_vial <- as_edge_graph(file_rutas_todas);
	// B. Crear la red del metro
		red_metro <- as_edge_graph(file_metro);
		create estacion from: file_estaciones {
			passengers_waiting <- [];
		}
		// 2. ALGORITMO DE ASIGNACIÓN DE NOMBRES E IDs
        // Ordenamos las estaciones de SUR a NORTE basándonos en la coordenada Y
        list<estacion> estaciones_ordenadas <- estacion sort_by (each.location.y);
		loop i from: 0 to: length(estaciones_ordenadas) - 1 {
            estacion est <- estaciones_ordenadas[i];
            est.id_visual <- i + 1; // Asigna ID del 1 al 15
            
            // Si el ID coincide con el mapa, le ponemos nombre real
            if (nombres_clave contains_key (est.id_visual)) {
                est.nombre_real <- nombres_clave[est.id_visual];
                est.es_clave <- true;
                add est to: estaciones_clave; // La guardamos en lista prioritaria
            } else {
                est.nombre_real <- "E-" + string(est.id_visual);
            }
        }

		// D. Crear Trenes (inicialmente uno en cada extremo o distribuidos)
		create tren number: 4 {
			location <- one_of(estacion).location;
			passengers_onboard <- [];
		}

		//create edificio from: file_edificios;
	}

	// Generador de pasajeros constante (simulando hora pico)
 reflex generar_pasajeros when: every(intervalo_llegada_pasajeros #cycle) {
	// Lógica de Cuello de Botella:
        // 80% de probabilidad de que el pasajero aparezca en una estación CLAVE
        // 20% de probabilidad de que aparezca en cualquier otra
        
        estacion origen;
        estacion destino;
        
        if (flip(0.8)) { 
            origen <- one_of(estaciones_clave); // Quitumbe, Recreo, etc.
        } else {
            origen <- one_of(estacion);
        }
        
        // El destino suele ser diferente al origen
        destino <- one_of(estacion - origen);

		create pasajero {
			location <- any_location_in(origen.location + 100);
			target_station <- origen;
			final_destination <- destino;
		}

	}

}

// --- AGENTES ---
 species edificio {

	aspect base {
		draw shape color: #lightgray border: #gray;
	}

}

species estacion {
    int id_visual;
    string nombre_real;
    bool es_clave <- false;
    list<pasajero> passengers_waiting;

    reflex check_congestion {
        int cantidad <- length(passengers_waiting);
        if (cantidad > umbral_rojo) { color <- #red; } 
        else if (cantidad > umbral_amarillo) { color <- #orange; } 
        else { color <- #green; }
    }

    aspect base {
        // Si es clave, el círculo es más grande
        float tamano <- es_clave ? 40.0 : 20.0; 
        
        // Dibujar círculo de congestión
        draw circle(tamano + (length(passengers_waiting)/2)) color: color border: #red;
        
        // Dibujar Nombre solo si es clave o si hay zoom
        if (es_clave) {
            draw nombre_real color: #black size: 20 perspective: false at: location + {0, 50, 10};
        } else {
            draw string(id_visual) color: #black size: 12 perspective: false at: location + {0, 30, 5};
        }
    }
}

species tren skills: [moving] {
	list<pasajero> passengers_onboard;
	estacion next_stop;
	bool moving_forward <- true;

	reflex mover {
	// Moverse sobre el grafo del metro
 do wander on: red_metro speed: velocidad_tren;

		// Detectar si llegó a una estación
 estacion current_station <- estacion closest_to (self);
		if (self distance_to current_station < 50) {
			do manage_passengers(current_station);
		}

	}

	action manage_passengers (estacion est) {
	// 1. BAJAR PASAJEROS
 list<pasajero> to_alight <- passengers_onboard where (each.final_destination = est);
		ask to_alight {
			current_belief <- "arrived";
			location <- est.location;
		}

		passengers_onboard <- passengers_onboard - to_alight;

		// 2. SUBIR PASAJEROS (Simula cuello de botella si el tren está lleno)
 int espacios_libres <- capacidad_tren - length(passengers_onboard);
		if (espacios_libres > 0 and !empty(est.passengers_waiting)) {
			int a_subir <- min([espacios_libres, length(est.passengers_waiting)]);

			// Tomar los primeros N de la cola
 list<pasajero> subiendo <- est.passengers_waiting copy_between (0, a_subir);
			ask subiendo {
				myself.passengers_onboard << self;
				current_belief <- "on_train";
				location <- myself.location; // Desaparecen visualmente dentro del tren
 }

			// Actualizar la cola de la estación
 est.passengers_waiting <- est.passengers_waiting - subiendo;
		}

	}

	aspect base {
		draw rectangle(150, 50) color: #navy border: #aqua;
		draw string(length(passengers_onboard)) color: #black size: 15 at: location + {0, 0, 10};
	}

}

// --- BDI PARA PASAJEROS ---
 // Usamos control: simple_bdi para la estructura formal, 
 // pero usamos lógica directa para optimizar rendimiento con miles de agentes.
 species
pasajero skills: [moving] control: simple_bdi {
	estacion target_station;
	estacion final_destination;
	string current_belief <- "walking_to_station";

	// 1. CAMINAR A LA ESTACIÓN
 reflex walk_to_station when: current_belief = "walking_to_station" {
		do goto target: target_station on: red_vial speed: velocidad_pasajero;
		if (location distance_to target_station < 30) {
			current_belief <- "waiting";
			// Añadirse a la cola de la estación
 ask target_station {
				passengers_waiting << myself;
			}

		}

	}

	// 2. ESPERAR (El agente se queda quieto, la lógica la maneja el tren)
 reflex wait when: current_belief = "waiting" {
	// Solo visual: deambular un poco alrededor del punto de estación
 do wander amplitude: 20.0 speed: 1.0;
	}

	// 3. EN TREN (Se mueve con el tren)
 reflex riding when: current_belief = "on_train" {
	// Su ubicación es la del tren (manejado por el agente tren)
 }

	// 4. LLEGADA Y SALIDA
 reflex arrive when: current_belief = "arrived" {
	// Aquí podrías hacer que caminen a un edificio final
 do die; // Mueren al llegar para liberar memoria
 }

	// Si está esperando o en tren, visualmente desaparece o cambia
 aspect base {
		if (current_belief = "walking") {
			draw circle(15) color: #cyan;
		} else if (current_belief = "waiting") {
			draw circle(10) color: #yellow;
		}

	}

}

experiment Visualizacion type: gui {
	output {
		display mapa type: opengl background: #darkgray {
			graphics "Capas Estaticas" {
				loop g over: formas_rutas {
					draw g color: #black;
				}

				loop g over: lista_edificios {
					draw g color: #lightgray;
				}

				loop g over: lista_secundarias {
					draw g color: #violet;
				}

				loop g over: lista_principales {
					draw g color: #orange;
				}

				loop g over: formas_metro {
					draw g color: #black;
				}

			}

			//species edificio aspect: base;
 species estacion aspect: base;
			species tren aspect: base;
			species pasajero aspect: base;
		}
		// Monitor para ver si el sistema funciona
        display "Datos" {
            chart "Ocupacion Global" type: series {
                data "Pasajeros Esperando" value: sum(estacion collect length(each.passengers_waiting)) color: #red;
                data "Pasajeros en Tren" value: sum(tren collect length(each.passengers_onboard)) color: #blue;
            }
        }


	}

}
