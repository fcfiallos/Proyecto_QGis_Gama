model test_completo

global {
    // --- 1. CARGA DE ARCHIVOS (Tal cual aparecen en tu imagen) ---
    file file_edificios <- file("../includes/edificios.shp");
    file file_estaciones <- file("../includes/coordenadas_estaciones.shp");
    
    // Archivos de redes viales
    file file_rutas_todas <- file("../includes/ruta_metro_principales_secundarias.shp");
    file file_principales <- file("../includes/principales.shp");
    file file_secundarias <- file("../includes/secundarias.shp");
    file file_metro <- file("../includes/ruta_metro.shp");

    // --- 2. ENTORNO ---
    // Usamos el 'envelope' de edificios porque en tu imagen se ve que es el que 
    // tiene mayor ancho (14725m) para asegurar que todo entre en la pantalla.
    geometry shape <- envelope(file_edificios);
    
    init {
        // Creamos los agentes
        create edificio from: file_edificios;
        
        // Nota: Al cargar "rutas_todas" y luego las individuales, se dibujarán una encima de otra.
        // He puesto "rutas_todas" al fondo.
        create red_completa from: file_rutas_todas; 
        
        create via_secundaria from: file_secundarias;
        create via_principal from: file_principales;
        create metro from: file_metro;
        create estacion from: file_estaciones;
    }
}

// --- 3. DEFINICIÓN DE ESPECIES (Cómo se comportan y ven) ---

species edificio {
    aspect base {
        draw shape color: #lightgray border: #darkgray;
    }
}

species red_completa {
    aspect base {
        // Esta es la capa que contiene todo mezclado. La pintamos de negro fino al fondo.
        draw shape color: #black width: 1;
    }
}

species via_secundaria {
    aspect base {
        draw shape color: #white width: 1.5; // Blancas o gris muy claro
    }
}

species via_principal {
    aspect base {
        draw shape color: #orange width: 3; // Naranja y más gruesas
    }
}

species metro {
    aspect base {
        draw shape color: #blue width: 5; // Azul y muy gruesa
    }
}

species estacion {
    aspect base {
        // Dibuja el círculo rojo
        draw circle(30) color: #red border: #white;
        
        // Dibuja el texto. 
        // Usamos 'at: location + {0, 40}' para subir el texto 40 metros en el eje Y
        draw "Estación" color: #black size: 15 perspective: false at: location + {0, 40}; 
    }
}

// --- 4. EXPERIMENTO (Visualización) ---

experiment visualizacion type: gui {
    output {
        display mapa_completo type: opengl background: #gray {
            // El orden aquí define las capas (de abajo hacia arriba)
            
            // 1. Fondo: La red completa (mezclada)
            species red_completa aspect: base;
            
            // 2. Edificios
            species edificio aspect: base;
            
            // 3. Vías detalladas encima
            species via_secundaria aspect: base;
            species via_principal aspect: base;
            
            // 4. Lo más importante arriba: Metro y Estaciones
            species metro aspect: base;
            species estacion aspect: base;
        }
    }
}