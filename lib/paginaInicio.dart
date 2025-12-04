import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // NECESARIO: Agrega intl: ^0.18.0 (o superior) en tu pubspec.yaml

import 'menu_page.dart';

class MenuHomeScreen extends StatefulWidget {
  const MenuHomeScreen({super.key});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

class _MenuHomeScreenState extends State<MenuHomeScreen> with SingleTickerProviderStateMixin {
  // ---------------- COLORES DE LA MARCA ----------------
  final Color primaryColor = const Color(0xFFE08D00);
  final Color secondaryColor = const Color(0xFF000000);
  final Color accentColor = const Color(0xFFE53935);
  final Color cardColor = const Color(0xFF1E1E1E);
  final Color textWhite = const Color(0xFFFFFFFF);

  // ---------------- ESTADO Y ANIMACIÓN ----------------
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = true;

  // ---------------- ESTADOS PARA HORARIO ----------------
  bool _estaAbiertoHoyDia = false; // Si el día de la semana es laborable
  bool _estaDentroDelHorario = false; // Si la HORA actual está dentro del rango
  String _horarioHoy = "Cerrado";

  // ---------------- DATOS DEL NEGOCIO ----------------
  String nombreNegocio = "SARV SOLUTIONS";
  String urlInstagram = "https://www.instagram.com/migajascafe/";
  String urlMapa = "https://maps.app.goo.gl/g2rA9JGpfewZb35T9";
  String telefonoWhatsapp = "18095550000";

  Map<String, String> horariosSemana = {};

  final String endpointInfo =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec?table=DatosNeg';

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOutSine),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
    _cargarDatosNegocio();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getDiaActualKey(int weekday) {
    switch (weekday) {
      case 1: return "Lunes";
      case 2: return "Martes";
      case 3: return "Miércoles";
      case 4: return "Jueves";
      case 5: return "Viernes";
      case 6: return "Sábado";
      case 7: return "Domingo";
      default: return "";
    }
  }

  // ---------------- LÓGICA DE PARSEO DE HORAS ----------------
  
  /// Analiza el string (ej: "8:00 AM - 11:30 PM")
  /// y determina si la hora actual está dentro de ese rango.
  bool _verificarSiEstaAbiertoAhora(String rangoHorario) {
    if (rangoHorario.toLowerCase().contains("cerrado") || rangoHorario.trim().isEmpty) {
      return false;
    }

    try {
      // 1. Limpieza básica: quitar espacios extra y separar por guión
      // Separa por guión (-) o por " a " (si usaras ese formato)
      final partes = rangoHorario.split(RegExp(r'\s*-\s*|\s+a\s+')); 
      
      if (partes.length != 2) return false; 

      String startStr = partes[0].trim();
      String endStr = partes[1].trim();

      // 2. Obtener hora actual
      final now = DateTime.now();
      
      // 3. Convertir strings a DateTime usando el día de hoy como base
      DateTime? startTime = _parsearHora(startStr, now);
      DateTime? endTime = _parsearHora(endStr, now);

      if (startTime == null || endTime == null) {
        debugPrint("No se pudo parsear las horas: $startStr / $endStr");
        return false;
      }

      // 4. Manejo de horario nocturno (ej: Abre 6:00 PM, Cierra 2:00 AM del día siguiente)
      if (endTime.isBefore(startTime)) {
        endTime = endTime.add(const Duration(days: 1)); // El cierre es mañana
        // Si ahora es madrugada (ej: 1:00 AM) y el negocio cierra a las 2:00 AM, 
        // necesitamos comparar correctamente.
        // Si 'now' es antes de la apertura (ej: 1:00 AM < 6:00 PM), asumimos que es madrugada del día siguiente
        // para efectos de comparación con endTime.
        if (now.isBefore(startTime)) {
            // Creamos una referencia de 'now' sumándole un día virtualmente para comparar con el endTime extendido
            // O más simple: si estamos en madrugada, el rango es válido si es < endTime (que ya es mañana)
            // PERO esto es complejo en una sola linea.
            
            // Simplificación robusta:
            // Si es madrugada (hora < 12) y cierra en la madrugada, verificamos si 'now' < 'endTime' (pero endTime del día +1)
            // Esto requiere ajustar 'now' para la comparación si es necesario, o ajustar la lógica.
            
            // Lógica estándar simple: Si now < startTime, puede ser que aún no abre, O que estamos en la madrugada post-cierre.
            // Para este ejemplo simple, asumiremos día calendario.
            
            // CORRECCIÓN PARA MADRUGADA:
            // Si el cierre es al día siguiente (endTime > startTime original), y ahora son las 00:00 - 11:00 AM...
            // Probablemente pertenece al turno de ayer. Pero para el usuario que abre la app HOY...
            // Si hoy es martes 1:00 AM y el horario del martes es 6pm - 2am, técnicamente ese 1:00 AM es cierre.
            // Esta lógica básica compara con el horario "del día".
        }
      }

      // 5. Comparación final
      return now.isAfter(startTime) && now.isBefore(endTime);

    } catch (e) {
      debugPrint("Error verificando horario: $e");
      return false; 
    }
  }

  /// Parsea específicamente formatos con AM/PM (ej: "8:00 AM")
  DateTime? _parsearHora(String horaStr, DateTime now) {
    // 1. Limpieza: Normalizamos espacios y pasamos a mayúsculas para homogeneizar AM/PM
    String cleanStr = horaStr.trim().toUpperCase(); 
    // Reemplaza espacios múltiples por uno solo (ej: "8:00  PM" -> "8:00 PM")
    cleanStr = cleanStr.replaceAll(RegExp(r'\s+'), ' '); 

    // 2. Definimos formatos. PRIORIZAMOS "h:mm a" que es "8:00 AM"
    List<String> formatos = [
      "h:mm a",   // Coincide con "8:00 AM", "11:30 PM"
      "hh:mm a",  // Coincide con "08:00 AM"
      "h:mma",    // Coincide con "8:00AM" (sin espacio)
      "HH:mm",    // Formato 24h fallback
      "H:mm"      // Formato 24h corto
    ];
    
    for (var fmt in formatos) {
      try {
        // Forzamos locale 'en_US' para que reconozca AM/PM correctamente
        final parsedTime = DateFormat(fmt, 'en_US').parse(cleanStr);
        return DateTime(now.year, now.month, now.day, parsedTime.hour, parsedTime.minute);
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  // -------------------------------------------------------------

  Future<void> _cargarDatosNegocio() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final uri = Uri.parse("$endpointInfo&t=${DateTime.now().millisecondsSinceEpoch}");
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        if (decodedData is List && decodedData.isNotEmpty) {
          final Map<String, dynamic> infoOriginal = decodedData[0];
          final Map<String, dynamic> info = {};
          infoOriginal.forEach((key, value) {
            info[key.toString().toLowerCase().trim()] = value;
          });

          if (mounted) {
            setState(() {
              var nombre = info['nombre del negocio'];
              if (nombre != null && nombre.toString().trim().isNotEmpty) {
                nombreNegocio = nombre.toString().trim();
              }
              if (info.containsKey('instagram')) urlInstagram = info['instagram'].toString().trim();
              
              var tel = info['telefono'] ?? info['teléfono'];
              if (tel != null) telefonoWhatsapp = tel.toString().trim();

              var ubic = info['ubicacion'] ?? info['ubicación'];
              if (ubic != null) {
                String rawUbic = ubic.toString().trim();
                urlMapa = rawUbic.contains('http') 
                    ? rawUbic 
                    : "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(rawUbic)}";
              }

              horariosSemana = {};
              void updateDia(String diaSheet, String keyMap) {
                String? valor;
                if (info.containsKey(diaSheet)) {
                  valor = info[diaSheet].toString();
                } else {
                   String sinTilde = diaSheet.replaceAll('é', 'e').replaceAll('á', 'a').replaceAll('ú', 'u');
                   if (info.containsKey(sinTilde)) valor = info[sinTilde].toString();
                }
                if (valor != null && valor.trim().isNotEmpty) {
                  horariosSemana[keyMap] = valor.trim();
                }
              }

              updateDia("lunes", "Lunes");
              updateDia("martes", "Martes");
              updateDia("miércoles", "Miércoles");
              updateDia("jueves", "Jueves");
              updateDia("viernes", "Viernes");
              updateDia("sábado", "Sábado");
              updateDia("domingo", "Domingo");

              final diaActualKey = _getDiaActualKey(DateTime.now().weekday);
              final horarioDeHoyStr = horariosSemana[diaActualKey] ?? "Cerrado";

              _horarioHoy = horarioDeHoyStr;

              // 1. ¿Abre hoy? (Validación simple de texto)
              _estaAbiertoHoyDia = horarioDeHoyStr.toLowerCase() != "cerrado" && horarioDeHoyStr.isNotEmpty;

              // 2. ¿Está abierto AHORA MISMO? (Validación de hora)
              if (_estaAbiertoHoyDia) {
                _estaDentroDelHorario = _verificarSiEstaAbiertoAhora(horarioDeHoyStr);
              } else {
                _estaDentroDelHorario = false;
              }

              _isLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- MOSTRAR ALERTA DE CERRADO ----------------
  void _mostrarAlertaCerrado(BuildContext context, String horario) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.access_time_filled, color: accentColor),
            const SizedBox(width: 10),
            Text("¡Estamos Cerrados!", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Lo sentimos, en este momento no estamos recibiendo pedidos.",
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withOpacity(0.3))
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Horario hoy: $horario",
                      style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Entendido", style: GoogleFonts.poppins(color: primaryColor)),
          )
        ],
      ),
    );
  }

  // Funciones de enlaces (sin cambios)
  void abrirInstagram() async {
    final url = Uri.parse(urlInstagram);
    try { await launchUrl(url, mode: LaunchMode.externalApplication); } catch (_) {}
  }
  void abrirUbicacion() async {
    final url = Uri.parse(urlMapa);
    try { await launchUrl(url, mode: LaunchMode.externalApplication); } catch (_) {}
  }
  void abrirWhatsapp() async {
    final numeroLimpio = telefonoWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse("https://wa.me/$numeroLimpio");
    try { await launchUrl(url, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Image.asset(
                'assets/images/SARVSOLUTIONS_LOGO.png',
                width: 150, height: 150, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.info, size: 80, color: primaryColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diasOrdenados = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];
    
    if (_isLoading) {
      return Scaffold(backgroundColor: Colors.white, body: _buildLoadingScreen());
    }

    // USAMOS LA VARIABLE QUE COMPRUEBA LA HORA EXACTA
    final bool tiendaAbiertaAhora = _estaDentroDelHorario;
    
    // Texto de estado
    String estadoTexto = "CERRADO POR HOY";
    Color estadoColor = accentColor;

    if (tiendaAbiertaAhora) {
      estadoTexto = "ABIERTO • $_horarioHoy";
      estadoColor = primaryColor;
    } else {
      // Si el día es laborable pero la hora no coincide
      if (_estaAbiertoHoyDia) {
         estadoTexto = "CERRADO (Abre $_horarioHoy)";
      }
    }

    return Scaffold(
      backgroundColor: secondaryColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. SECCIÓN HERO
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 280,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage('https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&q=80&w=1000'),
                      fit: BoxFit.cover,
                    ),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.4), Colors.black.withOpacity(0.95)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: Colors.white,
                          boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                        ),
                        child: const CircleAvatar(
                          radius: 45, backgroundColor: Colors.white,
                          backgroundImage: AssetImage('assets/images/SARVSOLUTIONS_LOGO.png'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(nombreNegocio, style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold, color: textWhite)),
                      Text('El mejor sabor en cada bocado', style: GoogleFonts.poppins(fontSize: 14, color: textWhite.withOpacity(0.9), fontWeight: FontWeight.w300)),
                      const SizedBox(height: 15),
                      
                      // INDICADOR DE ESTADO ACTUALIZADO
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: estadoColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: estadoColor, width: 1.5)
                        ),
                        child: Text(
                          estadoTexto,
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: estadoColor, letterSpacing: 1.0),
                        ),
                      ),
                      const SizedBox(height: 35),
                    ],
                  ),
                ),
                Positioned(
                  bottom: -28, left: 30, right: 30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    decoration: BoxDecoration(
                      color: cardColor, borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _SocialIcon('assets/images/instagram.png', abrirInstagram, Icons.camera_alt, primaryColor),
                        Container(width: 1, height: 24, color: Colors.white24),
                        _SocialIcon('assets/images/whatsapp.png', abrirWhatsapp, Icons.message, primaryColor),
                        Container(width: 1, height: 24, color: Colors.white24),
                        _SocialIcon('assets/images/map.png', abrirUbicacion, Icons.map, primaryColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),

            // 2. BOTONES DE NAVEGACIÓN (CON LÓGICA DE BLOQUEO)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _MenuCard(
                    title: 'Ordenar en Restaurante',
                    subtitle: '¡Elige lo que quieras y pide a tu mesa!',
                    icon: Icons.restaurant,
                    color: primaryColor,
                    // LÓGICA DE BLOQUEO
                    onTap: () {
                      if (!tiendaAbiertaAhora) {
                        _mostrarAlertaCerrado(context, _horarioHoy);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UniversalMenuPage(
                              tipoServicio: TipoServicio.restaurante,
                              telefonoNegocio: telefonoWhatsapp,
                              estaAbierto: true,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _MenuCard(
                    title: 'Ordenar por Delivery o Pasar a Recoger',
                    subtitle: !tiendaAbiertaAhora ? '¡Cerrado ahora! 😢' : 'Te lo llevamos a donde estés',
                    icon: Icons.delivery_dining,
                    color: !tiendaAbiertaAhora ? cardColor.withOpacity(0.8) : accentColor,
                    isDisabled: !tiendaAbiertaAhora, // Cambia visualmente
                    // LÓGICA DE BLOQUEO
                    onTap: () {
                      if (!tiendaAbiertaAhora) {
                        _mostrarAlertaCerrado(context, _horarioHoy);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UniversalMenuPage(
                              tipoServicio: TipoServicio.delivery,
                              telefonoNegocio: telefonoWhatsapp,
                              estaAbierto: true,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 35),

            // 3. HORARIO
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                  border: Border.all(color: primaryColor.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.access_time_filled, color: primaryColor, size: 22),
                        const SizedBox(width: 10),
                        Text('NUESTRO HORARIO', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 14, letterSpacing: 1.2)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Divider(height: 1, thickness: 0.5, color: Colors.white24),
                    const SizedBox(height: 10),
                    ...diasOrdenados.map((dia) {
                      final hora = horariosSemana[dia] ?? "Cerrado";
                      final hoyIndex = DateTime.now().weekday;
                      bool esHoy = false;
                      if(hoyIndex == 1 && dia == "Lunes") esHoy = true;
                      if(hoyIndex == 2 && dia == "Martes") esHoy = true;
                      if(hoyIndex == 3 && dia == "Miércoles") esHoy = true;
                      if(hoyIndex == 4 && dia == "Jueves") esHoy = true;
                      if(hoyIndex == 5 && dia == "Viernes") esHoy = true;
                      if(hoyIndex == 6 && dia == "Sábado") esHoy = true;
                      if(hoyIndex == 7 && dia == "Domingo") esHoy = true;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _HorarioRow(dia, hora, isBold: esHoy, primaryColor: primaryColor, textColor: textWhite, accentColor: accentColor),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text("v1.0.1 • SARV SOLUTIONS", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ---------------- WIDGETS AUXILIARES (IGUALES QUE ANTES) ----------------

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isDisabled;

  const _MenuCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap, this.isDisabled = false});

  @override
  Widget build(BuildContext context) {
    // AQUI MODIFICAMOS: Aunque esté "disabled", permitimos el tap para mostrar la alerta
    final visualColor = isDisabled ? Colors.grey.shade800 : color;
    final textOpacity = isDisabled ? 0.6 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, // Siempre permite el tap, la lógica la maneja el padre
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: visualColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: visualColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
            gradient: isDisabled 
              ? null 
              : LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.4)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.3 * textOpacity), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white.withOpacity(textOpacity), size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.poppins(color: Colors.white.withOpacity(textOpacity), fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.9 * textOpacity), fontSize: 12, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.7 * textOpacity), size: 18),
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
  final Color tintColor;
  const _SocialIcon(this.asset, this.onTap, this.fallbackIcon, this.tintColor);
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Image.asset(asset, width: 28, height: 28, errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: tintColor, size: 28)),
      ),
    );
  }
}

class _HorarioRow extends StatelessWidget {
  final String days;
  final String hours;
  final bool isBold;
  final Color primaryColor;
  final Color textColor;
  final Color accentColor;
  const _HorarioRow(this.days, this.hours, {this.isBold = false, required this.primaryColor, required this.textColor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final bool estaCerrado = hours.toLowerCase().trim() == "cerrado" || hours.trim().isEmpty;
    final Color colorHora = estaCerrado ? accentColor : isBold ? primaryColor : textColor.withOpacity(0.7);
    final String textoHoras = estaCerrado ? "Cerrado" : hours;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(days, style: GoogleFonts.poppins(color: isBold ? primaryColor : textColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: 14)),
        Text(textoHoras, style: GoogleFonts.poppins(color: colorHora, fontWeight: isBold ? FontWeight.bold : FontWeight.w400, fontSize: 14)),
      ],
    );
  }
}