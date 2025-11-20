model test_completo_optimizado

global {
    // --- 1. CARGA DE ARCHIVOS ---
    file file_edificios <- file("../includes/edificios.shp");
    file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
    file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");
    file file_principales <- file("../includes/principales.shp");
    file file_secundarias <- file("../includes/secundarias.shp");
    file file_metro <- file("../includes/ruta_metro.shp");

    // --- 2. ENTORNO ---
    geometry shape <- envelope(file_edificios);
    
    // --- 3. LISTAS DE GEOMETRÍA (Para optimizar) ---
    // Usamos .contents para asegurarnos de obtener la lista de geometrías puras
    list<geometry> lista_edificios <- file_edificios.contents;
    list<geometry> lista_rutas_todas <- file_rutas_todas.contents;
    list<geometry> lista_principales <- file_principales.contents;
    list<geometry> lista_secundarias <- file_secundarias.contents;
    list<geometry> lista_metro <- file_metro.contents;

    init {
        // Solo creamos agentes para las estaciones
        create estacion from: file_estaciones;
    }
}

species estacion {
    aspect base {
        draw circle(30) color: #red border: #white;
        draw "Estación" color: #black size: 15 perspective: false at: location + {0, 40}; 
    }
}

experiment visualizacion type: gui {
    output {
        display mapa_completo type: opengl background: #gray {
            
            // CAPA OPTIMIZADA CON LOOPS
            graphics "Capas Estaticas" {
                loop g over: lista_rutas_todas { draw g color: #black; }
                loop g over: lista_edificios { draw g color: #lightgray; }
                loop g over: lista_secundarias { draw g color: #white; }
                loop g over: lista_principales { draw g color: #orange; }
                loop g over: lista_metro { draw g color: #blue; }
            }
            
            species estacion aspect: base;
        }
    }
}