model MetroQuitoCientifico

global {
    // --- 1. TIME AND SPEED CONFIGURATION ---
    float step <- 10.0 #s;
    // Visual factor (only for smooth or fast animation, does not affect calculations)
    float speed_factor <- 1.0 min: 0.1 max: 100.0; 
    
    // REAL PHYSICAL VARIABLE (Affects train movement and frequency)
    float operating_speed <- 38.0 min: 23.0 max: 73.0; 
    
    date starting_date <- date("2025-12-02 05:30:00");
    float decimal_hour update: current_date.hour + (current_date.minute / 60);
    string weekday <- "Monday" among: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
   
    // --- 2. PARAMETERS ---
    int num_cars <- 6 min: 3 max: 12;
    int max_train_capacity update: num_cars * 205;
    
    // Demand Sliders
    float demand_labrador <- 1.0 min: 0.0 max: 5.0;
    float demand_u_central <- 1.0 min: 0.0 max: 5.0;
    float demand_san_francisco <- 1.0 min: 0.0 max: 5.0;
    float demand_magdalena <- 1.0 min: 0.0 max: 5.0;
    float demand_recreo <- 1.0 min: 0.0 max: 5.0;
    float demand_quitumbe <- 1.0 min: 0.0 max: 5.0;

    // --- 3. DATA AND FILES ---
    map<string, int> target_passengers_day <- ["Monday"::185320, "Tuesday"::189886, "Wednesday"::188714, "Thursday"::194124, "Friday"::201723, "Saturday"::143324, "Sunday"::103810];
    map<string, int> station_capacities <- ["El Labrador"::450, "Jipijapa"::120, "Iñaquito"::180, "La Carolina"::280, "Pradera"::130, "Universidad Central"::320, "Ejido"::190, "Alameda"::160, "San Francisco"::350, "Magdalena"::300, "Recreo"::400, "Cardenal de la Torre"::140, "Solanda"::250, "Morán Valverde"::180, "Quitumbe"::500];
    
    int accumulated_trips_today <- 0;
    
    // Paths (Ensure the "charts" folder exists inside "results")
    string output_folder <- "../results/"; 
    string charts_folder <- "../results/charts/"; 
    string csv_system_state <- output_folder + "1_system_state.csv";
    string csv_trips <- output_folder + "2_trip_log.csv";
    
    file file_buildings <- file("../includes/edificios.shp");
    file file_stations <- file("../includes/coordenadas_estaciones.shp");
    file file_metro <- file("../includes/ruta_metro.shp");
    geometry shape <- envelope(file_buildings);
    graph metro_network;
    list<station> sorted_stations;
    list<string> main_stations <- ["El Labrador", "Universidad Central", "San Francisco", "Magdalena", "Recreo", "Quitumbe"];
    list<string> sorted_names <- ["El Labrador", "Jipijapa", "Iñaquito", "La Carolina", "Pradera", "Universidad Central", "Ejido", "Alameda", "San Francisco", "Magdalena", "Recreo", "Cardenal de la Torre", "Solanda", "Morán Valverde", "Quitumbe"];
    list<int> idx_north <- [0, 1, 2, 3, 4, 5];
    list<int> idx_center <-[6, 7, 8, 9, 10];
    list<int> idx_south <- [11, 12, 13, 14];

    bool clean_shift <- true;
    

    init {
        metro_network <- as_edge_graph(clean_network(list<geometry>(file_metro.contents), 5.0, true, true));
        create station from: file_stations;
        sorted_stations <- station sort_by (each.location.y);
        
        loop i from: 0 to: length(sorted_stations) - 1 {
            station est <- sorted_stations[i];
            est.real_name <- sorted_names[i];
            est.idx <- i;
            est.is_main <- main_stations contains est.real_name;
            est.max_capacity <- station_capacities[est.real_name];
        }

        do create_trains;

        // INITIALIZE CSV
        list<string> system_state_header <- ["Date","Decimal_Hour","Day","Num_Cars","Operating_Speed",
                                             "Total_Waiting","Total_In_Trains",
                                             "D_Labrador","D_Quitumbe","Wait_Labrador","Wait_UCentral","Wait_SanFrancisco",
                                             "Wait_Magdalena","Wait_Recreo","Wait_Quitumbe","Avg_Train_Occupation_Pct"];
        
        save system_state_header to: csv_system_state format: "csv" rewrite: true;
        
        list<string> trips_header <- ["Day","Departure_Time","Arrival_Time","Duration_Minutes","Origin","Destination","Num_Cars","Operating_Speed"];
        save trips_header to: csv_trips format: "csv" rewrite: true;
    }

    action create_trains {
        create train number: 9 {
            is_north_to_south <- true;
            location <- sorted_stations[0].location;
            status <- "resting";
        }
        create train number: 9 {
            is_north_to_south <- false;
            location <- sorted_stations[14].location;
            status <- "resting";
        }
    }
    

    // --- 1. SYSTEM DATA CSV SAVING (Every 10 min) ---
    reflex save_system_data when: (cycle > 0) and (every(10 #mn)) {
        int total_waiting <- sum(station collect length(each.passengers_waiting));
        int total_onboard <- sum(train collect length(each.passengers_onboard));
        float average_occupation <- 0.0;
        if (length(train) > 0) {
             average_occupation <- mean(train collect (length(each.passengers_onboard) / max_train_capacity)) * 100;
        }
        
        // Specific station data
        int wait_lab <- length(sorted_stations[0].passengers_waiting);
        int wait_uc <- length(sorted_stations[5].passengers_waiting);
        int wait_sf <- length(sorted_stations[8].passengers_waiting);
        int wait_mag <- length(sorted_stations[9].passengers_waiting);
        int wait_rec <- length(sorted_stations[10].passengers_waiting);
        int wait_qui <- length(sorted_stations[14].passengers_waiting);
        
        list<unknown> data_row <- [
            string(current_date), 
            decimal_hour, 
            weekday, 
            num_cars,
            operating_speed,
            total_waiting, 
            total_onboard, 
            demand_labrador, 
            demand_quitumbe, 
            wait_lab, wait_uc, wait_sf, wait_mag, wait_rec, wait_qui, 
            average_occupation
        ];
                            
        save data_row to: csv_system_state format: "csv" rewrite: false;
    }

    // --- 2. AUTOMATIC CHART IMAGE SAVING ---
    reflex save_charts {
        // Save at 10:00 (end of morning peak) and 20:00 (end of evening peak)
        bool is_saving_time <- (current_date.hour = 10 and current_date.minute = 0) or (current_date.hour = 20 and current_date.minute = 0);
        
        // Use 'mod' for frequency control
        if (is_saving_time and (cycle mod int(60/step) = 0)) { 
            string timestamp <- string(current_date, "HH-mm");
            string filename <- "Results_Cars" + num_cars + "_Speed" + int(operating_speed) + "_" + timestamp + ".png";
            
            // Use snapshot to save the display
            save snapshot("Results_Dashboard") to: charts_folder + filename;
            write "CHART SAVED: " + filename;
        }
    }

    // --- 3. SYSTEM CLOSURE CHECK ---
    reflex check_closure {
        float closure_hour <- (weekday = "Sunday") ? 22.0 : 23.0;

        if (decimal_hour >= closure_hour and clean_shift) {
            write "SHIFT CLOSURE: " + weekday;
            clean_shift <- false; 
            do pause;
        }

        if (decimal_hour >= closure_hour and !clean_shift) {
            do reset_flow;
            clean_shift <- true; 
        }
    }

    action reset_flow {
        starting_date <- (weekday = "Saturday" or weekday = "Sunday") ? date("2025-12-07 07:00:00") : date("2025-12-02 05:30:00");
        time <- 0.0;
        cycle <- 0;
        current_date <- starting_date;
        accumulated_trips_today <- 0;
        clean_shift <- true; 
        
        ask passenger { do die; }
        ask train { do die; }
        ask station { passengers_waiting <- []; }
        
        do create_trains;
        write "System reset at: " + string(current_date, "HH:mm");
    }
    

        reflex flow_controller {
        bool is_peak <- (decimal_hour >= 6.5 and decimal_hour <= 10.0) or (decimal_hour >= 17.0 and decimal_hour <= 20.0);
        float base_rate <- (float(target_passengers_day[weekday]) / 63000.0) * step;
        int num_pax <- int(base_rate * (is_peak ? 2.3 : 0.45));
        
        create passenger number: num_pax {
            start_time <- current_date; 
            
            float r <- rnd(0.0, 1.0);
            if (r < 0.478) { origin <- sorted_stations[one_of(idx_north)]; } 
            else if (r < 0.791) { origin <- sorted_stations[one_of(idx_center)]; } 
            else if (r < 0.921) { origin <- sorted_stations[one_of(idx_south)]; } 
            else { origin <- one_of(sorted_stations[0], sorted_stations[14]); }

            if (length(origin.passengers_waiting) >= origin.max_capacity) {
                do die; 
            } else {
                list<station> candidates <- sorted_stations where (each != origin);
                list<float> weights_list;
                loop est over: candidates {
                    float p <- 1.0;
                    if (est.real_name = "El Labrador") { p <- 2.0 * demand_labrador; } 
                    else if (est.real_name = "Quitumbe") { p <- 2.0 * demand_quitumbe; } 
                    else if (est.real_name = "Universidad Central") { p <- 1.5 * demand_u_central; } 
                    else if (est.real_name = "San Francisco") { p <- 1.5 * demand_san_francisco; } 
                    else if (est.real_name = "Magdalena") { p <- 1.5 * demand_magdalena; } 
                    else if (est.real_name = "Recreo") { p <- 1.5 * demand_recreo; } 
                    else if (est.is_main) { p <- 1.5; }

                    if (decimal_hour >= 6.5 and decimal_hour <= 10.0) {
                        if (idx_north contains est.idx or idx_center contains est.idx) { p <- p * 1.8; }
                    } else if (decimal_hour >= 17.0 and decimal_hour <= 20.0) {
                        if (idx_south contains est.idx) { p <- p * 1.8; }
                    }
                    weights_list << p;
                }

                destination <- candidates[rnd_choice(weights_list)];
                is_heading_south <- (destination.idx > origin.idx);
                location <- origin.location;
                ask origin { passengers_waiting << myself; }
                accumulated_trips_today <- accumulated_trips_today + 1;
            } 
        }

        if (every((is_peak ? 5.0 : 8.0) #mn)) {
            train tn <- first(train where (each.status = "resting" and each.is_north_to_south and time >= each.resting_end_time));
            if (tn != nil) { ask tn { status <- "traveling"; target_station_idx <- 1; } }

            train ts <- first(train where (each.status = "resting" and !each.is_north_to_south and time >= each.resting_end_time));
            if (ts != nil) { ask ts { status <- "traveling"; target_station_idx <- 13; } }
        } 
    }
}

species station {
    string real_name;
    int idx;
    bool is_main;
    int max_capacity;
    list<passenger> passengers_waiting;

    aspect base {
        float ratio <- length(passengers_waiting) / max_capacity;
        rgb traffic_light_color <- ratio < 0.5 ? #green : (ratio < 0.9 ? #orange : #red);
        draw square(is_main ? 120 : 70) color: traffic_light_color border: #black;
        if (is_main) {
            draw real_name + " [" + length(passengers_waiting) + "/" + max_capacity + "]" at: location + {150, 0} color: #white font: font("Arial", 16, #bold);
        } else {
            draw string(length(passengers_waiting)) + "/" + max_capacity at: location + {80, 80} color: #cyan font: font("Arial", 10, #bold);
        }
    }
}
    

species train skills: [moving] {
    bool is_north_to_south;
    string status;
    int target_station_idx;
    float resting_end_time;
    path current_path;
    list<passenger> passengers_onboard;

    reflex navigate when: status = "traveling" {
        station dest <- sorted_stations[target_station_idx];
        if (current_path = nil) {
            current_path <- path_between(metro_network, location, dest.location);
        }

        do follow path: current_path speed: operating_speed #km / #h;
        
        if (location distance_to dest.location < 20 #m) {
            bool is_terminal <- (is_north_to_south and target_station_idx = 14) or (!is_north_to_south and target_station_idx = 0);
            
            list<passenger> getting_off <- is_terminal ? passengers_onboard : passengers_onboard where (each.destination = dest);
            
            ask getting_off {
                float duration_minutes <- (current_date - self.start_time) / 60;
                list<unknown> trip_info <- [
                    weekday,
                    string(self.start_time, "HH:mm:ss"),
                    string(current_date, "HH:mm:ss"),
                    duration_minutes,
                    self.origin.real_name,
                    self.destination.real_name,
                    num_cars,
                    operating_speed
                ];
                save trip_info to: csv_trips format: "csv" rewrite: false;
                do die;
            }

            passengers_onboard <- passengers_onboard - getting_off;
            int available_spots <- max_train_capacity - length(passengers_onboard);
            list<passenger> waiting_pax <- dest.passengers_waiting where (each.is_heading_south = self.is_north_to_south);
            int num_boarding <- min([available_spots, length(waiting_pax)]);
            if (num_boarding > 0) {
                list<passenger> boarding_pax <- waiting_pax copy_between (0, num_boarding);
                passengers_onboard <<+ boarding_pax;
                dest.passengers_waiting <- dest.passengers_waiting - boarding_pax;
            }

            current_path <- nil;
            if (is_terminal) {
                status <- "resting";
                resting_end_time <- time + (7 * 60);
                is_north_to_south <- !is_north_to_south;
            } else {
                target_station_idx <- is_north_to_south ? target_station_idx + 1 : target_station_idx - 1;
            }
        }
    }

    aspect base {
        rgb train_color <- (status = "resting") ? #white : (is_north_to_south ? #skyblue : #orange);
        draw box(200, 40, 20) color: train_color rotate: heading;
        if (status != "resting") {
            draw string(length(passengers_onboard)) at: location + {0, -100} color: #yellow font: font("Arial", 14, #bold) anchor: #center;
        }
    }
}

species passenger {
    station origin;
    station destination;
    bool is_heading_south;
    date start_time; 
}


experiment MetroQuito type: gui {
    parameter "Weekday" var: weekday category: "Configuration" on_change: { ask world { do reset_flow; } };
    parameter "Train Cars" var: num_cars category: "Train Configuration" on_change: { ask world { do reset_flow; } };
    parameter "Operating Speed (km/h)" var: operating_speed category: "Train Configuration" min: 23.0 max: 73.0 step: 5.0 on_change: { ask world { do reset_flow; } };
    parameter "Animation Speed" var: speed_factor category: "Visualization";
    
    // Sliders
    parameter "D. Labrador" var: demand_labrador category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};
	parameter "D. U. Central" var: demand_u_central category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};
	parameter "D. San Francisco" var: demand_san_francisco category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};
	parameter "D. Magdalena" var: demand_magdalena category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};
	parameter "D. Recreo" var: demand_recreo category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};
	parameter "D. Quitumbe" var: demand_quitumbe category: "Demand" on_change: {
		ask world {
			do reset_flow;
		}
	};

    user_command "Manually Reset Shift" {
        ask world { do reset_flow; }
    }


    output {
        layout #split; 

        display "Results_Dashboard" type: opengl background: #black {
            graphics "Background" {
                loop g over: list<geometry>(file_buildings.contents) { draw g color: #darkgray; }
                loop g over: list<geometry>(file_metro.contents) { draw g color: #white width: 4; }
            }
            species station aspect: base;
            species train aspect: base;
            
            // --- RESTORED HUD ---
            graphics "HUD" {
                bool is_peak <- (decimal_hour >= 6.5 and decimal_hour <= 10.0) or (decimal_hour >= 17.0 and decimal_hour <= 20.0);
                draw "TIME: " + string(current_date, "HH:mm") at: {100, 2000} color: (is_peak ? #red : #green) font: font("Arial", 35, #bold);
                draw "DAY: " + weekday at: {100, 2800} color: #white font: font("Arial", 25, #bold);
                draw "TRIPS: " + accumulated_trips_today at: {100, 3600} color: #yellow font: font("Arial", 25, #bold);
                draw "TRAIN: " + num_cars + " Cars" at: {100, 4300} color: #orange font: font("Arial", 18);
            }
        }
    }
    
}