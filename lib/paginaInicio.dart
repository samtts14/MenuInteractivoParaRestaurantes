import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// dart:typed_data ya no es necesario ni la importación de base64

// Importamos la página unificada para la navegación del menú (que usa la tabla Productos)
import 'menu_page.dart';

class MenuHomeScreen extends StatefulWidget {
  const MenuHomeScreen({super.key});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

// Añadimos 'with SingleTickerProviderStateMixin' para usar animaciones
class _MenuHomeScreenState extends State<MenuHomeScreen> with SingleTickerProviderStateMixin {
  // ---------------- COLORES DE LA MARCA ----------------
  final Color primaryColor = const Color(0xFF8C5A3A);
  final Color secondaryColor = const Color(0xFFF2E8DC);
  final Color accentColor = const Color(0xFF3E2723);

  // ---------------- ESTADO DE CARGA Y ANIMACIÓN ----------------
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation; // NUEVO: Animación de desvanecimiento (opacidad)
  late Animation<Offset> _slideAnimation; // NUEVO: Animación de desplazamiento
  bool _isLoading = true; // Nuevo estado de carga para controlar el splash screen
  

  // ---------------- DATOS DEL NEGOCIO (Estado) ----------------
  // Valores por defecto (se actualizarán con DatosNeg)
  String nombreNegocio = "SARLUX App"; 
  String urlInstagram = "https://www.instagram.com/migajascafe/";
  String urlMapa = "https://maps.app.goo.gl/g2rA9JGpfewZb35T9";
  String telefonoWhatsapp = "18095550000"; 
  
  // AÑADIDO: Mapa para guardar el horario de cada día.
  Map<String, String> horariosSemana = {};

  // URL del Script apuntando a la pestaña 'DatosNeg' en el MISMO sheet.
  final String endpointInfo =
      'https://script.google.com/macros/s/AKfycbwr-CKWRDD0RLxbvfGnlC12wMnBJfPjwRd72YPuCI9bAZW-uHUFrv-EbqC8UJScgoWi/exec?table=DatosNeg';

  @override
  void initState() {
    super.initState();
    
    // 1. Inicializar el controlador de animación. Usaremos un solo controlador para todos los efectos.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Un poco más lenta para el fade/slide
    );

    // 2. Definir la animación de opacidad (Fade): de 0.0 a 1.0
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    // 3. Definir la animación de desplazamiento (Slide): de (-0.2 en Y) a (0.0 en Y)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.2), // Inicia un poco arriba
      end: Offset.zero, // Termina en el centro
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutSine,
      ),
    );

    // 4. Definir la animación de escala (Pulso sutil): de 0.95 a 1.0
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    // 5. Iniciar la animación al cargar la pantalla.
    _animationController.forward();

    _cargarDatosNegocio();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }


  // Función para cargar los datos desde Google Sheets (Pestaña DatosNeg)
  Future<void> _cargarDatosNegocio() async {
    // Retraso para que la animación se muestre al menos 500ms
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      debugPrint("Iniciando carga de pestaña DatosNeg...");
      // Agregamos un timestamp para evitar que el celular guarde una versión vieja en caché
      final uri = Uri.parse("$endpointInfo&t=${DateTime.now().millisecondsSinceEpoch}");
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        
        // Verificamos si devolvió un error (Map) o una lista de datos
        if (decodedData is Map && decodedData.containsKey('error')) {
          debugPrint("Error desde AppScript: ${decodedData['error']}");
        }

        if (decodedData is List && decodedData.isNotEmpty) {
          // Tomamos la primera fila de DatosNeg
          final Map<String, dynamic> infoOriginal = decodedData[0]; 
          
          // --- DETECTOR DE ERROR DE SCRIPT (Mantenerlo activo para diagnóstico) ---
          if (infoOriginal.containsKey('Nombre del Producto') || infoOriginal.containsKey('Precio')) {
            debugPrint("🚨 ERROR CRÍTICO DE SCRIPT 🚨");
            debugPrint("El script de Google sigue devolviendo la hoja 'Productos'.");
            debugPrint("SOLUCIÓN: Ve a Apps Script -> Implementar -> Nueva implementación para actualizar el código en la nube.");
          }
          // -----------------------------------

          // TRUCO: Normalizamos las claves para que no importen mayúsculas o espacios
          final Map<String, dynamic> info = {};
          infoOriginal.forEach((key, value) {
            info[key.toString().toLowerCase().trim()] = value;
          });
          
          debugPrint("Claves normalizadas recibidas: ${info.keys}"); 
          
          if (mounted) {
            setState(() {
              // 1. NOMBRE DEL NEGOCIO (Busca 'nombre del negocio')
              var nombre = info['nombre del negocio'];
              if (nombre != null && nombre.toString().trim().isNotEmpty) {
                nombreNegocio = nombre.toString().trim();
              }

              // 2. INSTAGRAM (Busca 'instagram')
              if (info.containsKey('instagram') && info['instagram'].toString().trim().isNotEmpty) {
                urlInstagram = info['instagram'].toString().trim();
              }
              
              // 3. TELÉFONO (Busca 'telefono' o 'teléfono')
              var tel = info['telefono'] ?? info['teléfono'];
              if (tel != null && tel.toString().trim().isNotEmpty) {
                telefonoWhatsapp = tel.toString().trim();
              }

              // 4. UBICACIÓN (Busca 'ubicacion' o 'ubicación')
              var ubic = info['ubicacion'] ?? info['ubicación'];
              if (ubic != null && ubic.toString().trim().isNotEmpty) {
                String rawUbic = ubic.toString().trim();
                // Si la celda contiene "http", asumimos que es un enlace directo
                if (rawUbic.toLowerCase().contains('http')) {
                  urlMapa = rawUbic;
                } else {
                  // Si es texto (ej: "Calle 5, Santiago"), creamos un link de búsqueda
                  urlMapa = "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(rawUbic)}";
                }
              }

              // 5. HORARIOS (Actualización dinámica)
              horariosSemana = {}; // Limpiamos antes de actualizar

              void updateDia(String diaSheet, String keyMap) {
                String? valor;
                
                // 1. Buscamos exactamente como viene (ej: "miércoles")
                if (info.containsKey(diaSheet)) {
                  valor = info[diaSheet].toString();
                } 
                // 2. Si no está, buscamos sin tilde (ej: "miercoles") por seguridad
                else {
                   String sinTilde = diaSheet.replaceAll('é', 'e').replaceAll('á', 'a').replaceAll('ú', 'u');
                   if (info.containsKey(sinTilde)) {
                     valor = info[sinTilde].toString();
                   }
                }

                // Solo guardamos si el valor no está vacío. Si está vacío, se mostrará "Cerrado" por defecto en el build.
                if (valor != null && valor.trim().isNotEmpty) {
                  horariosSemana[keyMap] = valor.trim();
                } 
              }

              // Usamos los nombres EXACTOS de tus columnas (en minúscula porque así normalizamos `info`)
              updateDia("lunes", "Lunes");
              updateDia("martes", "Martes");
              updateDia("miércoles", "Miércoles"); 
              updateDia("jueves", "Jueves");
              updateDia("viernes", "Viernes");
              updateDia("sábado", "Sábado"); 
              updateDia("domingo", "Domingo");
              
              _isLoading = false; // Datos cargados, ocultamos la carga
            });
          }
        } else {
          debugPrint("La pestaña DatosNeg está vacía o el script devolvió una lista vacía.");
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Excepción cargando DatosNeg: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- FUNCIONES DE ENLACES ----------------
  void abrirInstagram() async {
    final url = Uri.parse(urlInstagram);
    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
        debugPrint("No se pudo abrir Instagram: $e");
    }
  }

  void abrirUbicacion() async {
    final url = Uri.parse(urlMapa);
    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
        debugPrint("No se pudo abrir Mapa: $e");
    }
  }

  void abrirWhatsapp() async {
    // Limpiamos el número de símbolos no numéricos
    final numeroLimpio = telefonoWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse("https://wa.me/$numeroLimpio"); 
    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
        debugPrint("No se pudo abrir WhatsApp: $e");
    }
  }
  
  // Widget que muestra el logo animado durante la carga
  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        // Combinamos la Transición de Desvanecimiento (Fade) y Desplazamiento (Slide)
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition( // Mantenemos una sutil animación de escala al final de la aparición
              scale: _scaleAnimation,
              // Usamos Image.asset con la ruta del archivo SARLUX2.png
              child: Image.asset(
                'assets/images/Sarlux_logo.png', // <--- RUTA DE TU IMAGEN
                width: 150, 
                height: 150, 
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.info, size: 80, color: Color(0xFF8C5A3A)), // Fallback por si la imagen no carga
              ),
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Orden de los días para mostrarlos en la lista
    final diasOrdenados = [
      "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"
    ];
    
    // Si está cargando, muestra la pantalla de carga con el logo animado
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildLoadingScreen(),
      );
    }

    return Scaffold(
      backgroundColor: secondaryColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. SECCIÓN HERO (Encabezado con Imagen, Logo y Redes)
            Stack(
              clipBehavior: Clip.none,
              children: [
                // A. Fondo con imagen
                Container(
                  height: 280,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(
                          'https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&q=80&w=1000'),
                      fit: BoxFit.cover,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(40),
                        bottomRight: Radius.circular(40),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // B. Contenido Central
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 45,
                          backgroundColor: Color.fromARGB(255, 230, 230, 230), // Usar un color gris claro en lugar de Colors.grey[200]
                          backgroundImage: AssetImage('assets/images/Sarlux_logo.png'),
                          // Manejo de error de la imagen de logo para el CircleAvatar
                          // Nota: AssetImage no usa onBackgroundImageError, por lo que usaremos un fallback simple
                          // Nota 2: Si el logo.png en 'assets/images/logo.png' no existe, esto fallará. Se asume que existe.
                          child: null, 
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        // AQUÍ SE USA EL NOMBRE DINÁMICO
                        nombreNegocio, 
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            const Shadow(
                              blurRadius: 10.0,
                              color: Colors.black45,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'El mejor sabor en cada bocado',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),

                // C. Barra Social Flotante (Dinámica)
                Positioned(
                  bottom: -28,
                  left: 30,
                  right: 30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.15),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _SocialIcon('assets/images/instagram.png', abrirInstagram, Icons.camera_alt),
                        Container(width: 1, height: 24, color: const Color.fromARGB(255, 224, 224, 224)), // Reemplazando Colors.grey[200]
                        _SocialIcon('assets/images/whatsapp.png', abrirWhatsapp, Icons.message),
                        Container(width: 1, height: 24, color: const Color.fromARGB(255, 224, 224, 224)), // Reemplazando Colors.grey[200]
                        _SocialIcon('assets/images/map.png', abrirUbicacion, Icons.map),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 60),

            // 2. BOTONES DE NAVEGACIÓN
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _MenuCard(
                    title: 'Comer en Restaurante',
                    subtitle: 'Escanea el código o pide a tu mesa',
                    icon: Icons.restaurant,
                    color: primaryColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UniversalMenuPage(
                            tipoServicio: TipoServicio.restaurante,
                            telefonoNegocio: telefonoWhatsapp,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _MenuCard(
                    title: 'Pedir Delivery',
                    subtitle: 'Te lo llevamos a donde estés',
                    icon: Icons.delivery_dining,
                    color: accentColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UniversalMenuPage(
                            tipoServicio: TipoServicio.delivery,
                            telefonoNegocio: telefonoWhatsapp,)
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 35),

            // 3. HORARIO DINÁMICO POR DÍA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ],
                  border: Border.all(color: primaryColor.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.access_time_filled, color: primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'NUESTRO HORARIO',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Divider(height: 1, thickness: 0.5),
                    const SizedBox(height: 10),
                    
                    // Generación dinámica de la lista de días
                    ...diasOrdenados.map((dia) {
                      final hora = horariosSemana[dia] ?? "Cerrado";
                      // Obtenemos el día actual para resaltarlo
                      final hoyIndex = DateTime.now().weekday; // 1 = Lunes, 7 = Domingo
                      
                      // Mapeo simple de índice a String para comparar
                      bool esHoy = false;
                      // El mapeo de weekday a nombre de día: 1=Lunes, 7=Domingo
                      if(hoyIndex == 1 && dia == "Lunes") esHoy = true;
                      if(hoyIndex == 2 && dia == "Martes") esHoy = true;
                      if(hoyIndex == 3 && dia == "Miércoles") esHoy = true;
                      if(hoyIndex == 4 && dia == "Jueves") esHoy = true;
                      if(hoyIndex == 5 && dia == "Viernes") esHoy = true;
                      if(hoyIndex == 6 && dia == "Sábado") esHoy = true;
                      if(hoyIndex == 7 && dia == "Domingo") esHoy = true;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _HorarioRow(dia, hora, isBold: esHoy),
                      );
                    }).toList(),

                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
            
            Text(
              "v1.0.0 • SARLUX App",
              style: GoogleFonts.poppins(color: const Color.fromARGB(255, 189, 189, 189), fontSize: 11), // Reemplazando Colors.grey[400]
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ---------------- WIDGETS AUXILIARES ----------------

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            gradient: LinearGradient(
              colors: [
                color,
                Color.lerp(color, Colors.black, 0.2)!, 
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.7), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final String asset;
  final VoidCallback onTap;
  final IconData fallbackIcon;

  const _SocialIcon(this.asset, this.onTap, this.fallbackIcon);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          asset,
          width: 28,
          height: 28,
          errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: const Color(0xFF8C5A3A), size: 28),
        ),
      ),
    );
  }
}

class _HorarioRow extends StatelessWidget {
  final String days;
  final String hours;
  final bool isBold;

  const _HorarioRow(this.days, this.hours, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          days,
          style: GoogleFonts.poppins(
            color: isBold ? const Color(0xFF8C5A3A) : const Color.fromARGB(255, 85, 85, 85), // Reemplazando Colors.black54
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500, 
            fontSize: 14
          ),
        ),
        Text(
          hours,
          style: GoogleFonts.poppins(
            color: isBold ? const Color(0xFF8C5A3A) : const Color.fromARGB(255, 51, 51, 51), // Reemplazando Colors.black87
            fontWeight: isBold ? FontWeight.bold : FontWeight.w400, 
            fontSize: 14
          ),
        ),
      ],
    );
  }
}