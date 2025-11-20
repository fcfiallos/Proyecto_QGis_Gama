model test_minimo

global {
    // Carga el archivo
    file edificios <- file("../includes/edificios.shp");
    
    // IMPORTANTE: Define la forma y tamaño del mundo basándose en el archivo
    geometry shape <- envelope(edificios);
    
    init {
        create casa from: edificios;
    }
}

species casa {
    aspect base {
        draw shape color: #red;
    }
}

experiment prueba type: gui {
    output {
        display vista {
            species casa aspect: base;
        }
    }
}