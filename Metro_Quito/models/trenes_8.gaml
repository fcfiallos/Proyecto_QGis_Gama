model MetroQuitoCientifico

global {
    // --- 1. CONFIGURACIÓN DE TIEMPO Y VELOCIDAD ---
    float step <- 10.0 #s;
    // Factor visual (solo para que la animación se vea fluida o rápida, no afecta cálculos)
    float factor_velocidad <- 1.0 min: 0.1 max: 100.0; 
    
    // VARIABLE FÍSICA REAL (Afecta el movimiento y frecuencia de trenes)
    float velocidad_operativa <- 38.0 min: 23.0 max: 73.0; 
    
    date starting_date <- date("2025-12-02 05:30:00");
    float hora_decimal update: current_date.hour + (current_date.minute / 60);
    string dia_semana <- "Monday" among: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
   
    // --- 2. PARÁMETROS ---
    int num_vagones <- 6 min: 3 max: 12;
    int capacidad_max_tren update: num_vagones * 205;
    
    // Sliders Demanda
    float d_labrador <- 1.0 min: 0.0 max: 5.0;
    float d_u_central <- 1.0 min: 0.0 max: 5.0;
    float d_san_francisco <- 1.0 min: 0.0 max: 5.0;
    float d_magdalena <- 1.0 min: 0.0 max: 5.0;
    float d_recreo <- 1.0 min: 0.0 max: 5.0;
    float d_quitumbe <- 1.0 min: 0.0 max: 5.0;

    // --- 3. DATOS Y ARCHIVOS ---
    map<string, int> pasajeros_objetivo_dia <- ["Lunes"::185320, "Martes"::189886, "Miércoles"::188714, "Jueves"::194124, "Viernes"::201723, "Sábado"::143324, "Domingo"::103810];
    map<string, int> aforos_estaciones <- ["El Labrador"::450, "Jipijapa"::120, "Iñaquito"::180, "La Carolina"::280, "Pradera"::130, "Universidad Central"::320, "Ejido"::190, "Alameda"::160, "San Francisco"::350, "Magdalena"::300, "Recreo"::400, "Cardenal de la Torre"::140, "Solanda"::250, "Morán Valverde"::180, "Quitumbe"::500];
    
    int viajes_acumulados_hoy <- 0;
    
    // Rutas (Asegúrate que la carpeta "charts" exista dentro de "results")
    string output_folder <- "../results/"; 
    string charts_folder <- "../results/charts/"; 
    string csv_estado_sistema <- output_folder + "1_estado_sistema.csv";
    string csv_viajes <- output_folder + "2_registro_viajes.csv";
    
    file file_edificios <- file("../includes/edificios.shp");
    file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
    file file_metro <- file("../includes/ruta_metro.shp");
    geometry shape <- envelope(file_edificios);
    graph red_metro;
    list<estacion> estaciones_ordenadas;
    list<string> principales <- ["El Labrador", "Universidad Central", "San Francisco", "Magdalena", "Recreo", "Quitumbe"];
    list<string> nombres_ordenados <- ["El Labrador", "Jipijapa", "Iñaquito", "La Carolina", "Pradera", "Universidad Central", "Ejido", "Alameda", "San Francisco", "Magdalena", "Recreo", "Cardenal de la Torre", "Solanda", "Morán Valverde", "Quitumbe"];
    list<int> idx_norte <- [0, 1, 2, 3, 4, 5];
    list<int> idx_centro <- [6, 7, 8, 9, 10];
    list<int> idx_sur <- [11, 12, 13, 14];

    bool jornada_limpia <- true;

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

        // INICIALIZAR CSV
        list<string> header_estado <- ["Fecha","Hora_Decimal","Dia","Num_Vagones","Velocidad_Operativa",
                                       "Total_Esperando","Total_En_Trenes",
                                       "D_Labrador","D_Quitumbe","Esp_Labrador","Esp_UCentral","Esp_SanFrancisco",
                                       "Esp_Magdalena","Esp_Recreo","Esp_Quitumbe","Ocupacion_Promedio_Trenes_Porc"];
        
        save header_estado to: csv_estado_sistema format: "csv" rewrite: true;
        
        list<string> header_viajes <- ["Dia","Hora_Salida","Hora_Llegada","Duracion_Minutos","Origen","Destino","Num_Vagones","Velocidad_Operativa"];
        save header_viajes to: csv_viajes format: "csv" rewrite: true;
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

    // --- 1. GUARDADO DE CSV (Cada 10 min) ---
    reflex guardar_datos_sistema when: (cycle > 0) and (every(10 #mn)) {
        int total_waiting <- sum(estacion collect length(each.passengers_waiting));
        int total_onboard <- sum(tren collect length(each.pasajeros_onboard));
        float ocupacion_promedio <- 0.0;
        if (length(tren) > 0) {
             ocupacion_promedio <- mean(tren collect (length(each.pasajeros_onboard) / capacidad_max_tren)) * 100;
        }
        
        // Datos específicos
        int esp_lab <- length(estaciones_ordenadas[0].passengers_waiting);
        int esp_uc <- length(estaciones_ordenadas[5].passengers_waiting);
        int esp_sf <- length(estaciones_ordenadas[8].passengers_waiting);
        int esp_mag <- length(estaciones_ordenadas[9].passengers_waiting);
        int esp_rec <- length(estaciones_ordenadas[10].passengers_waiting);
        int esp_qui <- length(estaciones_ordenadas[14].passengers_waiting);
        
        list<unknown> data_row <- [
            string(current_date), 
            hora_decimal, 
            dia_semana, 
            num_vagones,
            velocidad_operativa,
            total_waiting, 
            total_onboard, 
            d_labrador, 
            d_quitumbe, 
            esp_lab, esp_uc, esp_sf, esp_mag, esp_rec, esp_qui, 
            ocupacion_promedio
        ];
                            
        save data_row to: csv_estado_sistema format: "csv" rewrite: false;
    }

    // --- 2. GUARDADO DE IMAGENES DE GRÁFICAS (Automático) ---
    reflex guardar_graficos {
        // Guardamos a las 10:00 (fin pico mañana) y 20:00 (fin pico tarde)
        bool momento_guardado <- (current_date.hour = 10 and current_date.minute = 0) or (current_date.hour = 20 and current_date.minute = 0);
        
        // Usamos 'mod' para el control de frecuencia
        if (momento_guardado and (cycle mod int(60/step) = 0)) { 
            string timestamp <- string(current_date, "HH-mm");
            string nombre_archivo <- "Resultados_Vag" + num_vagones + "_Vel" + int(velocidad_operativa) + "_" + timestamp + ".png";
            
            // Usamos snapshot para guardar el display
            save snapshot("Tablero_Resultados") to: charts_folder + nombre_archivo;
            write "GRÁFICO GUARDADO: " + nombre_archivo;
        }
    }

    reflex verificar_cierre {
        float h_cierre <- (dia_semana = "Domingo") ? 22.0 : 23.0;

        if (hora_decimal >= h_cierre and jornada_limpia) {
            write "CIERRE DE JORNADA: " + dia_semana;
            jornada_limpia <- false; 
            do pause;
        }

        if (hora_decimal >= h_cierre and !jornada_limpia) {
            do reiniciar_fluyente;
            jornada_limpia <- true; 
        }
    }

    action reiniciar_fluyente {
        starting_date <- (dia_semana = "Sábado" or dia_semana = "Domingo") ? date("2025-12-07 07:00:00") : date("2025-12-02 05:30:00");
        time <- 0.0;
        cycle <- 0;
        current_date <- starting_date;
        viajes_acumulados_hoy <- 0;
        jornada_limpia <- true; 
        
        ask pasajero { do die; }
        ask tren { do die; }
        ask estacion { passengers_waiting <- []; }
        
        do crear_trenes;
        write "Sistema reiniciado a las: " + string(current_date, "HH:mm");
    }

    reflex controlador_flujo {
        bool es_pico <- (hora_decimal >= 6.5 and hora_decimal <= 10.0) or (hora_decimal >= 17.0 and hora_decimal <= 20.0);
        float tasa_base <- (float(pasajeros_objetivo_dia[dia_semana]) / 63000.0) * step;
        int num_pax <- int(tasa_base * (es_pico ? 2.3 : 0.45));
        
        create pasajero number: num_pax {
            hora_inicio <- current_date; 
            
            float r <- rnd(0.0, 1.0);
            if (r < 0.478) { origen <- estaciones_ordenadas[one_of(idx_sur)]; } 
            else if (r < 0.791) { origen <- estaciones_ordenadas[one_of(idx_norte)]; } 
            else if (r < 0.921) { origen <- estaciones_ordenadas[one_of(idx_centro)]; } 
            else { origen <- one_of(estaciones_ordenadas[0], estaciones_ordenadas[14]); }

            if (length(origen.passengers_waiting) >= origen.capacidad_max) {
                do die; 
            } else {
                list<estacion> candidatos <- estaciones_ordenadas where (each != origen);
                list<float> pesos_lista;
                loop est over: candidatos {
                    float p <- 1.0;
                    if (est.nombre_real = "El Labrador") { p <- 2.0 * d_labrador; } 
                    else if (est.nombre_real = "Quitumbe") { p <- 2.0 * d_quitumbe; } 
                    else if (est.nombre_real = "Universidad Central") { p <- 1.5 * d_u_central; } 
                    else if (est.nombre_real = "San Francisco") { p <- 1.5 * d_san_francisco; } 
                    else if (est.nombre_real = "Magdalena") { p <- 1.5 * d_magdalena; } 
                    else if (est.nombre_real = "Recreo") { p <- 1.5 * d_recreo; } 
                    else if (est.es_principal) { p <- 1.5; }

                    if (hora_decimal >= 6.5 and hora_decimal <= 10.0) {
                        if (idx_norte contains est.idx or idx_centro contains est.idx) { p <- p * 1.8; }
                    } else if (hora_decimal >= 17.0 and hora_decimal <= 20.0) {
                        if (idx_sur contains est.idx) { p <- p * 1.8; }
                    }
                    pesos_lista << p;
                }

                destino <- candidatos[rnd_choice(pesos_lista)];
                va_al_sur <- (destino.idx > origen.idx);
                location <- origen.location;
                ask origen { passengers_waiting << myself; }
                viajes_acumulados_hoy <- viajes_acumulados_hoy + 1;
            } 
        }

        if (every((es_pico ? 5.0 : 8.0) #mn)) {
            tren tn <- first(tren where (each.estado = "descanso" and each.sentido_norte_a_sur and time >= each.tiempo_fin_descanso));
            if (tn != nil) { ask tn { estado <- "en_viaje"; estacion_objetivo_idx <- 1; } }

            tren ts <- first(tren where (each.estado = "descanso" and !each.sentido_norte_a_sur and time >= each.tiempo_fin_descanso));
            if (ts != nil) { ask ts { estado <- "en_viaje"; estacion_objetivo_idx <- 13; } }
        } 
    }
}

species estacion {
    string nombre_real;
    int idx;
    bool es_principal;
    int capacidad_max;
    list<pasajero> passengers_waiting;

    aspect base {
        float ratio <- length(passengers_waiting) / capacidad_max;
        rgb color_semaforo <- ratio < 0.5 ? #green : (ratio < 0.9 ? #orange : #red);
        draw square(es_principal ? 120 : 70) color: color_semaforo border: #black;
        if (es_principal) {
            draw nombre_real + " [" + length(passengers_waiting) + "/" + capacidad_max + "]" at: location + {150, 0} color: #white font: font("Arial", 16, #bold);
        } else {
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

        do follow path: camino_actual speed: velocidad_operativa #km / #h;
        
        if (location distance_to dest.location < 20 #m) {
            bool es_terminal <- (sentido_norte_a_sur and estacion_objetivo_idx = 14) or (!sentido_norte_a_sur and estacion_objetivo_idx = 0);
            
            list<pasajero> bajan <- es_terminal ? pasajeros_onboard : pasajeros_onboard where (each.destino = dest);
            
            ask bajan {
                float duracion_minutos <- (current_date - self.hora_inicio) / 60;
                list<unknown> info_viaje <- [
                    dia_semana,
                    string(self.hora_inicio, "HH:mm:ss"),
                    string(current_date, "HH:mm:ss"),
                    duracion_minutos,
                    self.origen.nombre_real,
                    self.destino.nombre_real,
                    num_vagones,
                    velocidad_operativa
                ];
                save info_viaje to: csv_viajes format: "csv" rewrite: false;
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
    date hora_inicio; 
}

experiment MetroQuito type: gui {
    parameter "Día" var: dia_semana category: "Configuración" on_change: { ask world { do reiniciar_fluyente; } };
    parameter "Vagones" var: num_vagones category: "Configuración Tren" on_change: { ask world { do reiniciar_fluyente; } };
    parameter "Velocidad Operativa (km/h)" var: velocidad_operativa category: "Configuración Tren" min: 23.0 max: 73.0 step: 5.0 on_change: { ask world { do reiniciar_fluyente; } };
    parameter "Velocidad Animación" var: factor_velocidad category: "Visualización";
    
    // Sliders
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

    user_command "Reiniciar Jornada Manualmente" {
        ask world { do reiniciar_fluyente; }
    }

    output {
        layout #split; 

        display "Mapa_Operativo" type: opengl background: #black {
            graphics "Fondo" {
                loop g over: list<geometry>(file_edificios.contents) { draw g color: #darkgray; }
                loop g over: list<geometry>(file_metro.contents) { draw g color: #white width: 4; }
            }
            species estacion aspect: base;
            species tren aspect: base;
            
            // --- AQUI ESTA EL HUD RESTAURADO ---
            graphics "HUD" {
                bool es_pico <- (hora_decimal >= 6.5 and hora_decimal <= 10.0) or (hora_decimal >= 17.0 and hora_decimal <= 20.0);
                draw "TIME: " + string(current_date, "HH:mm") at: {100, 2000} color: (es_pico ? #red : #green) font: font("Arial", 35, #bold);
                draw "DAY: " + dia_semana at: {100, 2800} color: #white font: font("Arial", 25, #bold);
                draw "TRIPS: " + viajes_acumulados_hoy at: {100, 3600} color: #yellow font: font("Arial", 25, #bold);
                draw "TRAIN: " + num_vagones + " Cars" at: {100, 4300} color: #orange font: font("Arial", 18);
            }
        }
        
/*
        display "Tablero_Resultados" refresh: every(5 #cycles) background: #white {
            
            // GRÁFICA 1: Serie Temporal
            chart "Evolución de Espera (Congestión Global)" type: series position: {0, 0} size: {1, 0.33} background: #white color: #black {
                data "Total Pasajeros Esperando" value: sum(estacion collect length(each.passengers_waiting)) color: #red thickness: 2.0;
                data "Total en Trenes" value: sum(tren collect length(each.pasajeros_onboard)) color: #blue;
            }

            // GRÁFICA 2: Barras (Bucle corregido)
            chart "Congestión Actual por Estación" type: histogram position: {0, 0.33} size: {0.5, 0.33} background: #white color: #black {
                loop e over: estaciones_ordenadas {
                    data e.nombre_real value: length(e.passengers_waiting) color: #orange;
                }
            }

            // GRÁFICA 3: Serie
            chart "Ocupación Promedio Trenes (%)" type: series position: {0.5, 0.33} size: {0.5, 0.33} background: #white color: #black y_range: [0, 100] {
                data "% Ocupación" value: (length(tren) > 0) ? mean(tren collect (length(each.pasajeros_onboard) / capacidad_max_tren)) * 100 : 0 color: #green thickness: 2.0;
                data "Límite Saturación (85%)" value: 85.0 color: #gray style: line;
            }
            
            graphics "Info_Config" position: {0, 0.66} size: {1, 0.33} {
                draw "CONFIGURACIÓN ACTUAL:" at: {50, 50} color: #black font: font("Arial", 20, #bold);
                draw "Vagones: " + num_vagones at: {50, 300} color: #blue font: font("Arial", 18);
                draw "Velocidad Operativa: " + velocidad_operativa + " km/h" at: {50, 550} color: #blue font: font("Arial", 18);
            }
        }
        * 
        */
    }
}