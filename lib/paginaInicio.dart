import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// La importación de dart:typed_data ya no es necesaria.

// Importamos la página unificada para la navegación del menú (que usa la tabla Productos)
import 'menu_page.dart';

class MenuHomeScreen extends StatefulWidget {
  const MenuHomeScreen({super.key});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

// Añadimos 'with SingleTickerProviderStateMixin' para usar animaciones
class _MenuHomeScreenState extends State<MenuHomeScreen> with SingleTickerProviderStateMixin {
  // ---------------- COLORES DE LA MARCA (PARMESANO STYLE) ----------------
  // Naranja Mostaza (Para botones principales y resaltados)
  final Color primaryColor = const Color(0xFFE08D00); 
  // Negro Puro (Fondo de pantalla principal)
  final Color secondaryColor = const Color(0xFF000000); 
  // Rojo Intenso (Para delivery)
  final Color accentColor = const Color(0xFFE53935); 
  // Gris Oscuro (Para fondo de tarjetas de horario y redes sobre el negro)
  final Color cardColor = const Color(0xFF1E1E1E); 
  // Blanco (Para textos sobre fondo oscuro)
  final Color textWhite = const Color(0xFFFFFFFF);

  // ---------------- ESTADO DE CARGA Y ANIMACIÓN ----------------
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation; 
  late Animation<Offset> _slideAnimation; 
  bool _isLoading = true; // Nuevo estado de carga para controlar el splash screen
  
  // ---------------- NUEVOS ESTADOS PARA HORARIO ----------------
  bool _estaAbiertoHoy = false; // Indica si hoy tiene horario (no vacío/cerrado)
  String _horarioHoy = "Cerrado"; // Almacena el horario de hoy o "Cerrado"
  

  // ---------------- DATOS DEL NEGOCIO (Estado) ----------------
  // Valores por defecto (se actualizarán con DatosNeg)
  String nombreNegocio = "SARV SOLUTIONS"; 
  String urlInstagram = "https://www.instagram.com/migajascafe/";
  String urlMapa = "https://maps.app.goo.gl/g2rA9JGpfewZb35T9";
  String telefonoWhatsapp = "18095550000"; 
  
  // Mapa para guardar el horario de cada día.
  Map<String, String> horariosSemana = {};

  // URL del Script apuntando a la pestaña 'DatosNeg' en el MISMO sheet.
  final String endpointInfo =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec?table=DatosNeg';

  @override
  void initState() {
    super.initState();
    
    // 1. Inicializar el controlador de animación.
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), 
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
      begin: const Offset(0.0, -0.2), 
      end: Offset.zero, 
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
  
  // Obtiene el nombre del día en español para la clave del mapa
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
        
        // Manejo de errores y verificación de lista
        if (decodedData is List && decodedData.isNotEmpty) {
          final Map<String, dynamic> infoOriginal = decodedData[0]; 
          
          // TRUCO: Normalizamos las claves para que no importen mayúsculas o espacios
          final Map<String, dynamic> info = {};
          infoOriginal.forEach((key, value) {
            info[key.toString().toLowerCase().trim()] = value;
          });
          
          debugPrint("Claves normalizadas recibidas: ${info.keys}"); 
          
          if (mounted) {
            setState(() {
              // 1. NOMBRE DEL NEGOCIO
              var nombre = info['nombre del negocio'];
              if (nombre != null && nombre.toString().trim().isNotEmpty) {
                nombreNegocio = nombre.toString().trim();
              }

              // 2. INSTAGRAM
              if (info.containsKey('instagram') && info['instagram'].toString().trim().isNotEmpty) {
                urlInstagram = info['instagram'].toString().trim();
              }
              
              // 3. TELÉFONO
              var tel = info['telefono'] ?? info['teléfono'];
              if (tel != null && tel.toString().trim().isNotEmpty) {
                telefonoWhatsapp = tel.toString().trim();
              }

              // 4. UBICACIÓN
              var ubic = info['ubicacion'] ?? info['ubicación'];
              if (ubic != null && ubic.toString().trim().isNotEmpty) {
                String rawUbic = ubic.toString().trim();
                if (rawUbic.toLowerCase().contains('http')) {
                  urlMapa = rawUbic;
                } else {
                  urlMapa = "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(rawUbic)}";
                }
              }

              // 5. HORARIOS (Actualización dinámica)
              horariosSemana = {}; 

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

                if (valor != null && valor.trim().isNotEmpty) {
                  horariosSemana[keyMap] = valor.trim();
                } 
              }

              // Usamos los nombres EXACTOS de tus columnas (en minúscula)
              updateDia("lunes", "Lunes");
              updateDia("martes", "Martes");
              updateDia("miércoles", "Miércoles"); 
              updateDia("jueves", "Jueves");
              updateDia("viernes", "Viernes");
              updateDia("sábado", "Sábado"); 
              updateDia("domingo", "Domingo");
              
              // 6. CÁLCULO DEL ESTADO DE HOY (ABIERTO/CERRADO)
              final diaActualKey = _getDiaActualKey(DateTime.now().weekday);
              final horarioDeHoy = horariosSemana[diaActualKey] ?? "Cerrado";

              _horarioHoy = horarioDeHoy;
              // Está abierto si el valor de la celda de hoy NO es "Cerrado" (insensible a mayúsculas) y NO está vacío.
              _estaAbiertoHoy = horarioDeHoy.trim().isNotEmpty && horarioDeHoy.toLowerCase() != "cerrado";

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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition( 
              scale: _scaleAnimation,
              child: Image.asset(
                'assets/images/SARVSOLUTIONS_LOGO.png', 
                width: 150, 
                height: 150, 
                fit: BoxFit.contain,
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
    
    // ---------------- CONFIGURACIÓN PARA CUANDO ESTÁ CERRADO ----------------
    final bool deliveryBloqueado = !_estaAbiertoHoy;
    final String estadoHoyTexto = _estaAbiertoHoy ? "ABIERTO HOY ${_horarioHoy}" : "CERRADO HOY";
    final Color estadoHoyColor = _estaAbiertoHoy ? primaryColor : accentColor; 

    return Scaffold(
      backgroundColor: secondaryColor, // FONDO DE LA APP: NEGRO
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
                  decoration: BoxDecoration(
                    image: const DecorationImage(
                      image: NetworkImage(
                          'https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&q=80&w=1000'),
                      fit: BoxFit.cover,
                    ),
                    borderRadius: const BorderRadius.only(
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
                          Colors.black.withOpacity(0.4),
                          Colors.black.withOpacity(0.95), 
                        ],
                      ),
                    ),
                  ),
                ),
                
                // B. Contenido Central (Incluyendo el indicador de estado)
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
                              color: primaryColor.withOpacity(0.4), 
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.white, 
                          backgroundImage: AssetImage('assets/images/SARVSOLUTIONS_LOGO.png'),
                          child: null, 
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        nombreNegocio, 
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: textWhite, 
                          shadows: [
                            const Shadow(
                              blurRadius: 10.0,
                              color: Colors.black,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'El mejor sabor en cada bocado',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: textWhite.withOpacity(0.9), 
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      
                      // COMIENZO DEL ESPACIO MODIFICADO
                      const SizedBox(height: 15), 
                      // ---------------- INDICADOR ABIERTO/CERRADO ----------------
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Un poco más de padding interno también
                        decoration: BoxDecoration(
                          color: estadoHoyColor.withOpacity(0.2), 
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: estadoHoyColor, width: 1.5)
                        ),
                        child: Text(
                          estadoHoyTexto,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: estadoHoyColor, 
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      // ---------------- FIN INDICADOR ----------------

                      const SizedBox(height: 35), // Espacio drástico
                      // FIN DEL ESPACIO MODIFICADO
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
                      color: cardColor, // Fondo Gris Oscuro
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
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

            // 2. BOTONES DE NAVEGACIÓN
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Botón "Comer en Restaurante"
                  _MenuCard(
                    title: 'Ordenar en Restaurante',
                    subtitle: '¡Elige lo que quieras y pide a tu mesa!',
                    icon: Icons.restaurant,
                    color: primaryColor, 
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UniversalMenuPage(
                            tipoServicio: TipoServicio.restaurante,
                            telefonoNegocio: telefonoWhatsapp,
                            estaAbierto: _estaAbiertoHoy, // PASANDO EL ESTADO DE APERTURA
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  // Botón "Pedir Delivery" (BLOQUEADO SI ESTÁ CERRADO)
                  _MenuCard(
                    title: 'Ordenar por Delivery',
                    subtitle: deliveryBloqueado ? '¡Cerrado hoy! 😢' : 'Te lo llevamos a donde estés', 
                    icon: Icons.delivery_dining,
                    color: deliveryBloqueado ? cardColor.withOpacity(0.8) : accentColor, 
                    isDisabled: deliveryBloqueado, 
                    onTap: deliveryBloqueado ? () {} : () { 
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UniversalMenuPage(
                            tipoServicio: TipoServicio.delivery,
                            telefonoNegocio: telefonoWhatsapp,
                            estaAbierto: _estaAbiertoHoy, // PASANDO EL ESTADO DE APERTURA
                          )
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
                  color: cardColor, 
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ],
                  border: Border.all(color: primaryColor.withOpacity(0.1)),
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
                    const Divider(height: 1, thickness: 0.5, color: Colors.white24), 
                    const SizedBox(height: 10),
                    
                    // Generación dinámica de la lista de días
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
                        child: _HorarioRow(
                          dia, 
                          hora, 
                          isBold: esHoy, 
                          primaryColor: primaryColor, 
                          textColor: textWhite,
                          accentColor: accentColor, 
                        ),
                      );
                    }).toList(),

                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
            
            Text(
              "v1.0.0 • SARV SOLUTIONS",
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11), 
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ---------------- WIDGETS AUXILIARES MODIFICADOS ----------------

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isDisabled; // NUEVO: Para bloquear el botón

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isDisabled = false, // Por defecto no está deshabilitado
  });

  @override
  Widget build(BuildContext context) {
    // Usamos el color base si no está deshabilitado, o un gris con menos opacidad si lo está
    final cardColor = isDisabled ? Colors.grey.shade700 : color;
    final textOpacity = isDisabled ? 0.5 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Si está deshabilitado, el onTap no hace nada
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: cardColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            // Usamos un degradado más sutil cuando está deshabilitado
            gradient: isDisabled
                ? null // Sin degradado si está deshabilitado
                : LinearGradient(
                    colors: [
                      color,
                      Color.lerp(color, Colors.black, 0.4)!, 
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
                  color: Colors.black.withOpacity(0.3 * textOpacity), // Oscurecemos el fondo si está deshabilitado
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white.withOpacity(textOpacity), size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(textOpacity),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9 * textOpacity),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
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
        child: Image.asset(
          asset,
          width: 28,
          height: 28,
          errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: tintColor, size: 28),
        ),
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
  final Color accentColor; // NUEVO: Color rojo

  const _HorarioRow(
    this.days, 
    this.hours, 
    {
      this.isBold = false,
      required this.primaryColor,
      required this.textColor,
      required this.accentColor, // Requerido
    }
  );

  @override
  Widget build(BuildContext context) {
    // Comprobamos si está "Cerrado" para aplicar el color rojo
    final bool estaCerrado = hours.toLowerCase().trim() == "cerrado" || hours.trim().isEmpty;
    
    // Si está cerrado, usamos el color acento (Rojo), si es hoy y está abierto, usamos primary (Naranja), si no, usamos el color de texto normal (Blanco/Gris)
    final Color colorHora = estaCerrado 
        ? accentColor
        : isBold ? primaryColor : textColor.withOpacity(0.7);

    // Si está cerrado, aseguramos que el texto sea "Cerrado" (con mayúscula)
    final String textoHoras = estaCerrado ? "Cerrado" : hours;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          days,
          style: GoogleFonts.poppins(
            // Naranja si es hoy (y no está cerrado), Blanco si no
            color: isBold ? primaryColor : textColor, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500, 
            fontSize: 14
          ),
        ),
        Text(
          textoHoras,
          style: GoogleFonts.poppins(
            color: colorHora,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w400, 
            fontSize: 14
          ),
        ),
      ],
    );
  }
}