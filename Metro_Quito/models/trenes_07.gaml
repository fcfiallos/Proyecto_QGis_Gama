model MetroQuitoCientifico

global {
// --- 1. CONFIGURACIÓN DE TIEMPO Y VELOCIDAD ---
	float step <- 10.0 #s;
	float factor_velocidad <- 1.0 min: 0.1 max: 20.0;
	float minimum_cycle_duration <- (step / 480.0) / factor_velocidad update: (step / 480.0) / factor_velocidad;
	date starting_date <- date("2025-12-02 05:30:00");
	float hora_decimal update: current_date.hour + (current_date.minute / 60);
	string dia_semana <- "Lunes" among: ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];

	// --- 2. PARÁMETROS DE DEMANDA Y VAGONES ---
	int num_vagones <- 6 min: 3 max: 12;
	int capacidad_max_tren update: num_vagones * 205;
	float d_labrador <- 1.0 min: 0.0 max: 5.0;
	float d_u_central <- 1.0 min: 0.0 max: 5.0;
	float d_san_francisco <- 1.0 min: 0.0 max: 5.0;
	float d_magdalena <- 1.0 min: 0.0 max: 5.0;
	float d_recreo <- 1.0 min: 0.0 max: 5.0;
	float d_quitumbe <- 1.0 min: 0.0 max: 5.0;

	// --- 3. DATOS REALES ---
	map<string, int> pasajeros_objetivo_dia <- ["Lunes"::185320, "Martes"::189886, "Miércoles"::188714, "Jueves"::194124, "Viernes"::201723, "Sábado"::143324, "Domingo"::103810];
	map<string, int>
	aforos_estaciones <- ["El Labrador"::450, "Jipijapa"::120, "Iñaquito"::180, "La Carolina"::280, "Pradera"::130, "Universidad Central"::320, "Ejido"::190, "Alameda"::160, "San Francisco"::350, "Magdalena"::300, "Recreo"::400, "Cardenal de la Torre"::140, "Solanda"::250, "Morán Valverde"::180, "Quitumbe"::500];
	int viajes_acumulados_hoy <- 0;
	file file_edificios <- file("../includes/edificios.shp");
	file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
	file file_metro <- file("../includes/ruta_metro.shp");
	geometry shape <- envelope(file_edificios);
	graph red_metro;
	list<estacion> estaciones_ordenadas;
	list<string> principales <- ["El Labrador", "Universidad Central", "San Francisco", "Magdalena", "Recreo", "Quitumbe"];
	list<string>
	nombres_ordenados <- ["El Labrador", "Jipijapa", "Iñaquito", "La Carolina", "Pradera", "Universidad Central", "Ejido", "Alameda", "San Francisco", "Magdalena", "Recreo", "Cardenal de la Torre", "Solanda", "Morán Valverde", "Quitumbe"];
	list<int> idx_norte <- [0, 1, 2, 3, 4, 5];
	list<int> idx_centro <- [6, 7, 8, 9, 10];
	list<int> idx_sur <- [11, 12, 13, 14];

	// Nueva variable para calcular el total de pasajeros en movimiento
	int total_pasajeros_en_trenes -> {sum(tren collect length(each.pasajeros_onboard))};
	bool jornada_limpia <- true; // Nueva variable para controlar el reinicio
	init {
		red_metro <- as_edge_graph(clean_network(list<geometry>(file_metro.contents), 5.0, true, true));
		create estacion from: file_estaciones;
		estaciones_ordenadas <- estacion sort_by (each.location.y);
		loop i from: 0 to: length(estaciones_ordenadas) - 1 {
			estacion est <- estaciones_ordenadas[i];
			est.nombre_real <- nombres_ordenados[i];
			est.idx <- i;
			est.es_principal <- principales contains est.nombre_real;
			est.capacidad_max <- aforos_estaciones[est.nombre_real];
		}

		do crear_trenes;
	}

	action crear_trenes {
		create tren number: 9 {
			sentido_norte_a_sur <- true;
			location <- estaciones_ordenadas[0].location;
			estado <- "descanso";
		}

		create tren number: 9 {
			sentido_norte_a_sur <- false;
			location <- estaciones_ordenadas[14].location;
			estado <- "descanso";
		}

	}

	reflex verificar_cierre {
		float h_cierre <- (dia_semana = "Domingo") ? 22.0 : 23.0;

		// Si llegamos a la hora de cierre y la jornada aún no ha sido marcada como terminada
		if (hora_decimal >= h_cierre and jornada_limpia) {
			write "CIERRE DE JORNADA: " + dia_semana + ". Presione PLAY para reiniciar el mismo día.";
			jornada_limpia <- false; // Marcamos que la jornada terminó
			do pause;
		}

		// Si el usuario dio PLAY y la jornada estaba terminada, reiniciamos automáticamente
		if (hora_decimal >= h_cierre and !jornada_limpia) {
			do reiniciar_fluyente;
			jornada_limpia <- true; // Marcamos que ya está limpio para la nueva jornada
		}

	}

	action reiniciar_fluyente {
	// Definir fecha según el día seleccionado
		starting_date <- (dia_semana = "Sábado" or dia_semana = "Domingo") ? date("2025-12-07 07:00:00") : date("2025-12-02 05:30:00");
		time <- 0.0;
		cycle <- 0;
		current_date <- starting_date;
		viajes_acumulados_hoy <- 0;
		jornada_limpia <- true; // <--- MUY IMPORTANTE AÑADIR ESTO
		ask pasajero {
			do die;
		}

		ask tren {
			do die;
		}

		ask estacion {
			passengers_waiting <- [];
		}

		do crear_trenes;
		write "Sistema reiniciado a las: " + string(current_date, "HH:mm");
	}

	reflex controlador_flujo {
		bool es_pico <- (hora_decimal >= 6.5 and hora_decimal <= 10.0) or (hora_decimal >= 17.0 and hora_decimal <= 20.0);
		float tasa_base <- (float(pasajeros_objetivo_dia[dia_semana]) / 63000.0) * step;
		int num_pax <- int(tasa_base * (es_pico ? 2.3 : 0.45));
		create pasajero number: num_pax {
			float r <- rnd(0.0, 1.0);
			if (r < 0.478) {
				origen <- estaciones_ordenadas[one_of(idx_sur)];
			} else if (r < 0.791) {
				origen <- estaciones_ordenadas[one_of(idx_norte)];
			} else if (r < 0.921) {
				origen <- estaciones_ordenadas[one_of(idx_centro)];
			} else {
				origen <- one_of(estaciones_ordenadas[0], estaciones_ordenadas[14]);
			}

			if (length(origen.passengers_waiting) >= origen.capacidad_max) {
				do die;
			} else {
				list<estacion> candidatos <- estaciones_ordenadas where (each != origen);
				list<float> pesos_lista;
				loop est over: candidatos {
					float p <- 1.0;
					if (est.nombre_real = "El Labrador") {
						p <- 2.0 * d_labrador;
					} else if (est.nombre_real = "Quitumbe") {
						p <- 2.0 * d_quitumbe;
					} else if (est.nombre_real = "Universidad Central") {
						p <- 1.5 * d_u_central;
					} else if (est.nombre_real = "San Francisco") {
						p <- 1.5 * d_san_francisco;
					} else if (est.nombre_real = "Magdalena") {
						p <- 1.5 * d_magdalena;
					} else if (est.nombre_real = "Recreo") {
						p <- 1.5 * d_recreo;
					} else if (est.es_principal) {
						p <- 1.5;
					}

					if (hora_decimal >= 6.5 and hora_decimal <= 10.0) {
						if (idx_norte contains est.idx or idx_centro contains est.idx) {
							p <- p * 1.8;
						}

					} else if (hora_decimal >= 17.0 and hora_decimal <= 20.0) {
						if (idx_sur contains est.idx) {
							p <- p * 1.8;
						}

					}

					pesos_lista << p;
				}

				destino <- candidatos[rnd_choice(pesos_lista)];
				va_al_sur <- (destino.idx > origen.idx);
				location <- origen.location;
				ask origen {
					passengers_waiting << myself;
				}

				viajes_acumulados_hoy <- viajes_acumulados_hoy + 1;
			} }

		if (every((es_pico ? 5.0 : 8.0) #mn)) {
			tren tn <- first(tren where (each.estado = "descanso" and each.sentido_norte_a_sur and time >= each.tiempo_fin_descanso));
			if (tn != nil) {
				ask tn {
					estado <- "en_viaje";
					estacion_objetivo_idx <- 1;
				}

			}

			tren ts <- first(tren where (each.estado = "descanso" and !each.sentido_norte_a_sur and time >= each.tiempo_fin_descanso));
			if (ts != nil) {
				ask ts {
					estado <- "en_viaje";
					estacion_objetivo_idx <- 13;
				}

			}

		} }

	reflex verificar_cierre {
		float h_cierre <- (dia_semana = "Domingo") ? 22.0 : 23.0;
		if (hora_decimal >= h_cierre) {
			write "CIERRE: " + dia_semana + " " + string(current_date, "HH:mm") + ". Pausando.";
			do pause;
		}

	} }

species estacion {
	string nombre_real;
	int idx;
	bool es_principal;
	int capacidad_max;
	list<pasajero> passengers_waiting;

	aspect base {
		float ratio <- length(passengers_waiting) / capacidad_max;
		rgb color_semaforo <- ratio < 0.5 ? #green : (ratio < 0.9 ? #orange : #red);

		// Dibujamos el cuadrado de la estación
		draw square(es_principal ? 120 : 70) color: color_semaforo border: #black;
		if (es_principal) {
		// PARA ESTACIONES PRINCIPALES:
		// Dibujamos Nombre + [Pasajeros/Capacidad] todo a la derecha
			draw nombre_real + " [" + length(passengers_waiting) + "/" + capacidad_max + "]" at: location + {150, 0} // Ajustamos posición a la derecha
			color: #white font: font("Arial", 16, #bold);
		} else {
		// PARA EL RESTO DE ESTACIONES:
		// Mantenemos solo el número pequeño en cian para no saturar el mapa
			draw string(length(passengers_waiting)) + "/" + capacidad_max at: location + {80, 80} color: #cyan font: font("Arial", 10, #bold);
		}

	}

}

species tren skills: [moving] {
	bool sentido_norte_a_sur;
	string estado;
	int estacion_objetivo_idx;
	float tiempo_fin_descanso;
	path camino_actual;
	list<pasajero> pasajeros_onboard;

	reflex navegar when: estado = "en_viaje" {
		estacion dest <- estaciones_ordenadas[estacion_objetivo_idx];
		if (camino_actual = nil) {
			camino_actual <- path_between(red_metro, location, dest.location);
		}

		do follow path: camino_actual speed: 40.0 #km / #h;
		if (location distance_to dest.location < 20 #m) {
			bool es_terminal <- (sentido_norte_a_sur and estacion_objetivo_idx = 14) or (!sentido_norte_a_sur and estacion_objetivo_idx = 0);
			list<pasajero> bajan <- es_terminal ? pasajeros_onboard : pasajeros_onboard where (each.destino = dest);
			ask bajan {
				do die;
			}

			pasajeros_onboard <- pasajeros_onboard - bajan;
			int cupo <- capacidad_max_tren - length(pasajeros_onboard);
			list<pasajero> esperan <- dest.passengers_waiting where (each.va_al_sur = self.sentido_norte_a_sur);
			int n_suben <- min([cupo, length(esperan)]);
			if (n_suben > 0) {
				list<pasajero> suben <- esperan copy_between (0, n_suben);
				pasajeros_onboard <<+ suben;
				dest.passengers_waiting <- dest.passengers_waiting - suben;
			}

			camino_actual <- nil;
			if (es_terminal) {
				estado <- "descanso";
				tiempo_fin_descanso <- time + (7 * 60);
				sentido_norte_a_sur <- !sentido_norte_a_sur;
			} else {
				estacion_objetivo_idx <- sentido_norte_a_sur ? estacion_objetivo_idx + 1 : estacion_objetivo_idx - 1;
			}

		}

	}

	aspect base {
		rgb color_tren <- (estado = "descanso") ? #white : (sentido_norte_a_sur ? #skyblue : #orange);
		draw box(200, 40, 20) color: color_tren rotate: heading;
		if (estado != "descanso") {
			draw string(length(pasajeros_onboard)) at: location + {0, -100} color: #yellow font: font("Arial", 14, #bold) anchor: #center;
		}

	}

}

species pasajero {
	estacion origen;
	estacion destino;
	bool va_al_sur;
}

experiment MetroQuito type: gui {
	parameter "Día" var: dia_semana category: "Configuración" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "Vagones" var: num_vagones category: "Tren" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "Velocidad Animación" var: factor_velocidad category: "Tiempo";
	parameter "D. Labrador" var: d_labrador category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "D. U. Central" var: d_u_central category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "D. San Francisco" var: d_san_francisco category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "D. Magdalena" var: d_magdalena category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "D. Recreo" var: d_recreo category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};
	parameter "D. Quitumbe" var: d_quitumbe category: "Demanda" on_change: {
		ask world {
			do reiniciar_fluyente;
		}

	};

	// ESTO AÑADE UN BOTÓN EN LA INTERFAZ
	user_command "Reiniciar Jornada Manualmente" {
		ask world {
			do reiniciar_fluyente;
		}

	}

	output {
		display "Mapa" type: opengl background: #black {
			graphics "Fondo" {
				loop g over: list<geometry>(file_edificios.contents) {
					draw g color: #darkgray;
				}

				loop g over: list<geometry>(file_metro.contents) {
					draw g color: #white width: 4;
				}

			}

			species estacion aspect: base;
			species tren aspect: base;
			graphics "HUD" {
				bool es_pico <- (hora_decimal >= 6.5 and hora_decimal <= 10.0) or (hora_decimal >= 17.0 and hora_decimal <= 20.0);
				draw "HORA: " + string(current_date, "HH:mm") at: {100, 2000} color: (es_pico ? #red : #green) font: font("Arial", 35, #bold);
				draw "DÍA: " + dia_semana at: {100, 2800} color: #white font: font("Arial", 25, #bold);
				draw "VIAJES: " + viajes_acumulados_hoy at: {100, 3600} color: #yellow font: font("Arial", 25, #bold);
				draw "TREN: " + num_vagones + " Vagones" at: {100, 4300} color: #orange font: font("Arial", 18);
			}

		}

		display "Estadisticas_Metro" refresh: every(10 #cycles) {

		// GRAFICA 1: Ocupación actual de cada tren (Histograma)
			chart "Pasajeros por Tren (Estado Actual)" type: histogram background: #black color: #white y_range: [0, capacidad_max_tren] position: {0, 0} size: {1, 0.5} {

			// CORRECCIÓN: Quitamos el "descanso ? #white" para que no fallen los fines de semana
			// Azul si va al Sur (True), Naranja si va al Norte (False)
				datalist tren value: tren collect length(each.pasajeros_onboard) legend: tren collect each.name color: tren collect (each.sentido_norte_a_sur ? #blue : #orange);

				// Mensajes de referencia (con valor 0 para que no creen barras extra con colores raros)
				data "Sentido Norte-Sur (Azul)" value: 0 color: #blue;
				data "Sentido Sur-Norte (Naranja)" value: 0 color: #orange;
			}

			// GRAFICA 2: Evolución de pasajeros a lo largo de las horas (Series)
			chart "Pasajeros Totales en el Sistema por Hora" type: series background: #black color: #white position: {0, 0.5} size: {1, 0.5} {
				if (cycle > 1) {
					data "Pasajeros en tránsito" value: sum(tren collect length(each.pasajeros_onboard)) color: #yellow marker: false;
				}

			}

		}

	}

}