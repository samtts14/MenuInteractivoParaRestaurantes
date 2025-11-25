import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// Importamos la página unificada para la navegación del menú (que usa la tabla Productos)
import 'menu_page.dart';

class MenuHomeScreen extends StatefulWidget {
  const MenuHomeScreen({super.key});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

class _MenuHomeScreenState extends State<MenuHomeScreen> {
  // ---------------- COLORES DE LA MARCA ----------------
  final Color primaryColor = const Color(0xFF8C5A3A);
  final Color secondaryColor = const Color(0xFFF2E8DC);
  final Color accentColor = const Color(0xFF3E2723);

  // ---------------- DATOS DEL NEGOCIO (Estado) ----------------
  // Valores por defecto (se actualizarán con DatosNeg)
  String nombreNegocio = "Migajas Café"; 
  String urlInstagram = "https://www.instagram.com/migajascafe/";
  String urlMapa = "https://maps.app.goo.gl/g2rA9JGpfewZb35T9";
  String telefonoWhatsapp = "18095550000"; 
  
  // AÑADIDO: Mapa para guardar el horario de cada día.
  Map<String, String> horariosSemana = {};

  // URL del Script apuntando a la pestaña 'DatosNeg' en el MISMO sheet.
  // IMPORTANTE: Si hiciste una "Nueva Implementación" y la URL cambió, actualízala aquí.
  final String endpointInfo =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec?table=DatosNeg';

  @override
  void initState() {
    super.initState();
    _cargarDatosNegocio();
  }

  // Función para cargar los datos desde Google Sheets (Pestaña DatosNeg)
  Future<void> _cargarDatosNegocio() async {
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
          return;
        }

        if (decodedData is List && decodedData.isNotEmpty) {
          // Tomamos la primera fila de DatosNeg
          final Map<String, dynamic> infoOriginal = decodedData[0]; 
          
          // --- DETECTOR DE ERROR DE SCRIPT (Mantenerlo activo para diagnóstico) ---
          if (infoOriginal.containsKey('Nombre del Producto') || infoOriginal.containsKey('Precio')) {
            debugPrint("🚨 ERROR CRÍTICO DE SCRIPT 🚨");
            debugPrint("El script de Google sigue devolviendo la hoja 'Productos'.");
            debugPrint("SOLUCIÓN: Ve a Apps Script -> Implementar -> Nueva implementación para actualizar el código en la nube.");
            // No salimos con return aquí, ya que el nombre del negocio y demás info
            // podrían estar presentes incluso en un JSON de 'Productos' si se repiten las claves.
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
            });
          }
        } else {
          debugPrint("La pestaña DatosNeg está vacía o el script devolvió una lista vacía.");
        }
      }
    } catch (e) {
      debugPrint("Excepción cargando DatosNeg: $e");
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

  @override
  Widget build(BuildContext context) {
    // Orden de los días para mostrarlos en la lista
    final diasOrdenados = [
      "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"
    ];

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
                        child: CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: const AssetImage('assets/images/logo.png'),
                          onBackgroundImageError: (_,__) => const Icon(Icons.coffee, size: 40),
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
                        Container(width: 1, height: 24, color: Colors.grey[200]),
                        _SocialIcon('assets/images/whatsapp.png', abrirWhatsapp, Icons.message),
                        Container(width: 1, height: 24, color: Colors.grey[200]),
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
                          builder: (_) => const UniversalMenuPage(tipoServicio: TipoServicio.restaurante),
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
                          builder: (_) => const UniversalMenuPage(tipoServicio: TipoServicio.delivery),
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
                          'HORARIO DE ATENCIÓN',
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
              "v1.0.0 • HyperBit App",
              style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 11),
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
            color: isBold ? const Color(0xFF8C5A3A) : Colors.black54, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500, 
            fontSize: 14
          ),
        ),
        Text(
          hours,
          style: GoogleFonts.poppins(
            color: isBold ? const Color(0xFF8C5A3A) : Colors.black87, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.w400, 
            fontSize: 14
          ),
        ),
      ],
    );
  }
}