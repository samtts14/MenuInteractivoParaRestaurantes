import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'paginaInicio.dart'; 

void main() {
  runApp(const CafeteriaApp());
}

class CafeteriaApp extends StatelessWidget {
  const CafeteriaApp({super.key});

  @override
  Widget build(BuildContext context) {
 
    const primaryColor = Color(0xFF8C5A3A); 
    const secondaryColor = Color(0xFFF2E8DC); 

    return MaterialApp(
      title: 'Menú Migajas Café',
      debugShowCheckedModeBanner: false,
      
      // TEMA GLOBAL: Aplica colores y fuentes a toda la aplicación automáticamente
      theme: ThemeData(
        useMaterial3: true, 
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          background: secondaryColor,
          primary: primaryColor,
          secondary: const Color(0xFF3E2723), 
        ),
        
        // Esto hace que todos los Text() de la app usen Poppins por defecto
        textTheme: GoogleFonts.poppinsTextTheme(),
        
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: primaryColor),
        ),
      ),
      
      home: const MenuHomeScreen(), 
    );
  }
}