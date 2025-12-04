import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // NECESARIO PARA GPS
import 'productos.dart';

// Enum para saber en qué modo estamos
enum TipoServicio { restaurante, delivery }

class UniversalMenuPage extends StatefulWidget {
  final TipoServicio tipoServicio;
  final String telefonoNegocio;
  final bool estaAbierto; 

  const UniversalMenuPage({
    super.key, 
    required this.tipoServicio,
    required this.telefonoNegocio,
    required this.estaAbierto,
  });

  @override
  State<UniversalMenuPage> createState() => _UniversalMenuPageState();
}

class _UniversalMenuPageState extends State<UniversalMenuPage> {
  // ---------------- CONFIGURACIÓN ----------------
  final String baseUrl =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec';
  
  // ---------------- ESTADO ----------------
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  String categoriaSeleccionada = "Todas";
  bool cargando = true;
  String filtroBusqueda = '';
  final Map<Producto, bool> _justAdded = {}; 

  // CARRITO Y NOTAS
  final Map<Producto, int> carrito = {}; 
  // Mapa para guardar notas específicas por nombre de producto
  final Map<String, String> notasPorProducto = {}; 
  // Controlador para nota general
  final TextEditingController _notaGeneralController = TextEditingController();

  List<Map<Producto, int>> historialRondas = []; 

  // Variables para el Carrusel
  final int _maxPages = 10000; 
  int get _initialPage => _maxPages ~/ 2;
  int get _numOffers => productos.where((p) => p.enOferta).length;

  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _paginaActual = 0;
  Timer? _timer;

  // ---------------- COLORES DE LA MARCA ----------------
  final primaryColor = const Color(0xFFE08D00); // Naranja Mostaza
  final secondaryColor = const Color(0xFF000000); // Negro Puro (Fondo)
  final cardColor = const Color(0xFF1E1E1E); // Gris Oscuro (Tarjetas)
  final accentColor = const Color(0xFFE53935); // Rojo (Ofertas/Acentos)
  final textWhite = const Color(0xFFFFFFFF); // Blanco
  final cartColor = const Color(0xFFE08D00); 

  bool get esDelivery => widget.tipoServicio == TipoServicio.delivery;
  bool get estaAbierto => widget.estaAbierto; 
  bool get estaCerrado => !widget.estaAbierto; 

  @override
  void initState() {
    super.initState();
    _cargarProductos(); 

    _pageController.addListener(() {
      int next = _pageController.page?.round() ?? 0;
      if (next != _paginaActual) {
        if (mounted) setState(() => _paginaActual = next);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_numOffers == 0 || !_pageController.hasClients) return;
      _pageController.animateToPage(
        _pageController.page!.toInt() + 1,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    _notaGeneralController.dispose();
    super.dispose();
  }

  // ---------------- PERSISTENCIA INTELIGENTE ----------------
  String _normalize(String text) => text.toLowerCase().trim();

  Future<void> _guardarCarrito() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final Map<String, int> carritoSimple = {};
      carrito.forEach((p, c) => carritoSimple[p.nombre] = c);
      
      final List<Map<String, int>> historialSimple = historialRondas.map((ronda) {
        final Map<String, int> rondaMap = {};
        ronda.forEach((p, c) => rondaMap[p.nombre] = c);
        return rondaMap;
      }).toList();

      await prefs.setString('carrito_persistente', jsonEncode(carritoSimple));
      await prefs.setString('historial_persistente', jsonEncode(historialSimple));
      await prefs.setString('notas_productos', jsonEncode(notasPorProducto));

      if (!prefs.containsKey('hora_inicio_orden')) {
        await prefs.setString('hora_inicio_orden', DateTime.now().toUtc().toIso8601String());
      }
    } catch (e) {
      debugPrint("Error al guardar persistencia: $e");
    }
  }

  Future<void> _restaurarCarrito(List<Producto> productosReferencia) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final String? horaInicioStr = prefs.getString('hora_inicio_orden');
      if (horaInicioStr != null) {
        final DateTime horaInicio = DateTime.parse(horaInicioStr).toUtc();
        final DateTime ahora = DateTime.now().toUtc();
        final Duration diferencia = ahora.difference(horaInicio);

        if (diferencia.inHours >= 5) {
          debugPrint("Sesión caducada (5h+). Limpiando datos.");
          await _borrarDatosLocales(prefs);
          return; 
        }
      }
    } catch (e) {
      debugPrint("Error verificando tiempo: $e");
    }

    try {
      final String? carritoJson = prefs.getString('carrito_persistente');
      if (carritoJson != null) {
        final Map<String, dynamic> datos = jsonDecode(carritoJson);
        final Map<Producto, int> restaurado = {};
        
        datos.forEach((nom, cant) {
            try {
              final p = productosReferencia.firstWhere(
                (element) => _normalize(element.nombre) == _normalize(nom)
              );
              restaurado[p] = (cant as num).toInt(); 
            } catch (_) {}
        });
        
        if (restaurado.isNotEmpty && mounted) {
          setState(() { 
            carrito.clear(); 
            carrito.addAll(restaurado); 
          });
        }
      }
    } catch (e) { debugPrint("Error restaurando carrito: $e"); }

    try {
      final String? notasJson = prefs.getString('notas_productos');
      if (notasJson != null) {
        final Map<String, dynamic> datos = jsonDecode(notasJson);
        setState(() {
          notasPorProducto.clear();
          datos.forEach((k, v) => notasPorProducto[k] = v.toString());
        });
      }
    } catch (e) { debugPrint("Error notas: $e"); }

    try {
      final String? historialJson = prefs.getString('historial_persistente');
      if (historialJson != null) {
        final List<dynamic> listaRondas = jsonDecode(historialJson);
        final List<Map<Producto, int>> historialRestaurado = [];

        for (var ronda in listaRondas) {
          final Map<String, dynamic> rondaMap = ronda;
          final Map<Producto, int> rondaObj = {};
          rondaMap.forEach((nom, cant) {
            try {
              final p = productosReferencia.firstWhere(
                (element) => _normalize(element.nombre) == _normalize(nom)
              );
              rondaObj[p] = (cant as num).toInt();
            } catch (_) {}
          });
          if (rondaObj.isNotEmpty) historialRestaurado.add(rondaObj);
        }
        if (historialRestaurado.isNotEmpty && mounted) {
          setState(() => historialRondas = historialRestaurado);
        }
      }
    } catch (e) { debugPrint("Error restaurando historial: $e"); }
  }

  Future<void> _borrarDatosLocales(SharedPreferences prefs) async {
    await prefs.remove('carrito_persistente');
    await prefs.remove('historial_persistente');
    await prefs.remove('hora_inicio_orden');
    await prefs.remove('notas_productos');
    if (mounted) {
      setState(() {
        carrito.clear();
        historialRondas.clear();
        notasPorProducto.clear();
        _notaGeneralController.clear();
      });
    }
  }

  // ---------------- CARGA DE DATOS ----------------
  Future<void> _cargarProductos() async {
    try {
      final String urlConCacheBuster = '$baseUrl?table=Productos&v=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.get(Uri.parse(urlConCacheBuster));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Producto> listaFresca = _parsearProductos(data);

        if (mounted) {
          setState(() {
            productos = listaFresca;
            _aplicarFiltros();
            cargando = false;
          });
          
          final numOffers = listaFresca.where((p) => p.enOferta).length;
          if (_pageController.hasClients && _pageController.page == 0 && numOffers > 0) {
             _pageController.jumpToPage(_initialPage);
          }

          await _restaurarCarrito(listaFresca); 
        }
      } else {
          if (mounted) setState(() => cargando = false);
      }
    } catch (e) {
      debugPrint("Error cargando productos: $e");
      if (mounted && productos.isEmpty) setState(() => cargando = false);
    }
  }

  List<Producto> _parsearProductos(List<dynamic> jsonList) {
    return jsonList
        .map((e) => Producto.fromJson(e))
        .where((p) => 
            p.nombre.trim().isNotEmpty && 
            p.estado.trim().toLowerCase() == 'disponible' 
        )
        .toList();
  }

  // ---------------- LÓGICA DE NEGOCIO ----------------

  void _aplicarFiltros() {
    String norm(String s) => s.toLowerCase();
    final query = norm(filtroBusqueda);

    List<Producto> temp = productos.where((p) {
      final matchTexto = norm(p.nombre).contains(query) || norm(p.categoria).contains(query);
      final matchCat = categoriaSeleccionada == "Todas" || p.categoria == categoriaSeleccionada;
      
      if (categoriaSeleccionada == "Ofertas") {
        return matchTexto && p.enOferta;
      }
      return matchTexto && matchCat;
    }).toList();

    temp.sort((a, b) {
      if (a.enOferta && !b.enOferta) return -1;
      if (!a.enOferta && b.enOferta) return 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    setState(() {
      productosFiltrados = temp;
    });
  }

  void filtrarPorTexto(String query) {
    filtroBusqueda = query;
    _aplicarFiltros();
  }

  void seleccionarCategoria(String cat) {
    setState(() => categoriaSeleccionada = cat);
    _aplicarFiltros();
  }

  Future<void> gestionarCarrito(Producto p, bool agregar) async {
    if (estaCerrado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("El negocio está cerrado.", style: GoogleFonts.poppins()), backgroundColor: accentColor)
      );
      return;
    }

    setState(() {
      if (agregar) {
        carrito[p] = (carrito[p] ?? 0) + 1;
        _justAdded[p] = true;
        Timer(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _justAdded.remove(p));
        });
      } else {
        if (carrito[p] != null && carrito[p]! > 1) {
          carrito[p] = carrito[p]! - 1;
        } else {
          carrito.remove(p);
          notasPorProducto.remove(p.nombre);
        }
      }
    });
    
    await _guardarCarrito(); 
  }

  double getPrice(Producto p) =>
      (p.enOferta && p.precioOferta != null && p.precioOferta! > 0)
          ? p.precioOferta!
          : p.precio;

  double get totalCarrito =>
      carrito.entries.fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));
  
  double get totalGeneral {
    double total = totalCarrito;
    for (var ronda in historialRondas) {
      total += ronda.entries.fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));
    }
    return total;
  }

  // --- LÓGICA DE GEOLOCALIZACIÓN MEJORADA ---

  Future<Position?> _determinarPosicion(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        _mostrarAlertaGPS(context, 
          "El GPS está desactivado", 
          "Por favor enciende la ubicación para continuar."
        );
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado.'))
          );
        }
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        _mostrarAlertaPermisos(context);
      }
      return null;
    } 

    try {
      return await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
        desiredAccuracy: LocationAccuracy.high
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error obteniendo ubicación: $e'))
        );
      }
      return null;
    }
  }

  void _mostrarAlertaPermisos(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Text("Permisos Necesarios", style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          "El permiso de ubicación está bloqueado permanentemente. Debes ir a la configuración de la app y activarlo manualmente.",
          style: GoogleFonts.poppins(color: Colors.white70)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings(); 
            },
            child: const Text("Abrir Configuración", style: TextStyle(color: Colors.black)),
          )
        ],
      )
    );
  }

  void _mostrarAlertaGPS(BuildContext context, String titulo, String msj) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        title: Text(titulo, style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(msj, style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Entendido", style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  // --- LÓGICA DE ENVÍO POR WHATSAPP (ACTUALIZADA) ---
  
  void enviarPedidoWhatsApp() {
    if (estaCerrado) return;
    _mostrarDialogoDatosPedido();
  }

  void _mostrarDialogoDatosPedido() {
    final txtNombre = TextEditingController();
    final txtDireccion = TextEditingController();
    
    // 0: Escribir, 1: GPS, 2: Recoger
    int modoUbicacion = 0;
    
    bool obteniendoGPS = false;
    String? googleMapsLink;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          Widget buildOptionButton(int index, IconData icon, String label) {
            final isSelected = modoUbicacion == index;
            return Expanded(
              child: GestureDetector(
                onTap: () async {
                   // Si toca el de GPS (índice 1), ejecutamos lógica especial
                   if (index == 1) {
                     setDialogState(() { modoUbicacion = 1; obteniendoGPS = true; });
                     Position? pos = await _determinarPosicion(ctx);
                     if (pos != null) {
                       String link = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";
                       setDialogState(() { 
                         obteniendoGPS = false; 
                         googleMapsLink = link;
                       });
                     } else {
                       // Si falla, volvemos a modo manual por defecto
                       setDialogState(() { 
                         obteniendoGPS = false; 
                         modoUbicacion = 0; 
                       });
                     }
                   } else {
                     setDialogState(() { 
                       modoUbicacion = index; 
                       obteniendoGPS = false; 
                       googleMapsLink = null;
                     });
                   }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor.withOpacity(0.2) : Colors.black12,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? primaryColor : Colors.white10, width: 2)
                  ),
                  child: Column(
                    children: [
                      if (index == 1 && obteniendoGPS)
                        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2))
                      else
                        Icon(icon, color: isSelected ? primaryColor : Colors.white54, size: 24),
                      const SizedBox(height: 6),
                      Text(
                        label, 
                        textAlign: TextAlign.center, 
                        style: GoogleFonts.poppins(color: isSelected ? Colors.white : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)
                      )
                    ],
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: cardColor,
            scrollable: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(esDelivery ? Icons.delivery_dining : Icons.restaurant_menu, color: primaryColor),
                const SizedBox(width: 10),
                Expanded(child: Text(esDelivery ? "Datos de Envío" : "Confirmar Pedido", style: GoogleFonts.poppins(color: textWhite, fontWeight: FontWeight.bold, fontSize: 18))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- CAMPO NOMBRE (SIEMPRE VISIBLE) ---
                Text("¿A nombre de quién?", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: txtNombre,
                  style: GoogleFonts.poppins(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: "Tu Nombre",
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 20),

                // --- SECCIÓN DE DIRECCIÓN (SOLO SI ES DELIVERY) ---
                if (esDelivery) ...[
                  Text(
                    "Método de entrega:",
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  
                  // --- TRES OPCIONES: ESCRIBIR | GPS | RECOGER ---
                  Row(
                    children: [
                      buildOptionButton(0, Icons.edit_location_alt, "Escribir\nDirección"),
                      const SizedBox(width: 8),
                      buildOptionButton(1, Icons.my_location, "Ubicación\nGPS"),
                      const SizedBox(width: 8),
                      buildOptionButton(2, Icons.storefront, "Pasar a\nRecoger"),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- CONTENIDO VARIABLE SEGÚN SELECCIÓN ---
                  if (modoUbicacion == 0)
                    TextField(
                      controller: txtDireccion,
                      style: GoogleFonts.poppins(color: Colors.white),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: "Escribe tu dirección",
                        hintText: "Calle, #Casa, Sector...",
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.home, color: Colors.grey),
                      ),
                    )
                  else if (modoUbicacion == 1 && googleMapsLink != null)
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3))
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "¡Ubicación detectada! Se enviará el mapa exacto.",
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                            ),
                          )
                        ],
                      ),
                    )
                  else if (modoUbicacion == 2)
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primaryColor.withOpacity(0.3))
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.directions_walk, color: primaryColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Pasarás a recoger tu pedido por el local. No necesitas poner dirección.",
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                            ),
                          )
                        ],
                      ),
                    )
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Cancelar", style: GoogleFonts.poppins(color: Colors.red)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
                ),
                onPressed: obteniendoGPS ? null : () {
                  // VALIDACIONES
                  if (txtNombre.text.trim().isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text("Por favor escribe tu nombre.", style: GoogleFonts.poppins()))
                     );
                     return;
                  }

                  // Si es delivery, validamos dirección SOLO si no es "Recoger"
                  if (esDelivery && modoUbicacion == 0 && txtDireccion.text.trim().isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text("Por favor escribe una dirección.", style: GoogleFonts.poppins()))
                     );
                     return;
                  }
                  
                  Navigator.pop(ctx); // Cerrar diálogo
                  
                  // Preparar datos
                  String infoDireccion = "";
                  if (esDelivery) {
                    if (modoUbicacion == 1 && googleMapsLink != null) {
                      infoDireccion = "📍 *Ubicación GPS:* $googleMapsLink";
                    } else if (modoUbicacion == 2) {
                      infoDireccion = "🏃 *Método de Entrega:* PASARÉ A RECOGER";
                    } else {
                      infoDireccion = "🏠 *Dirección:* ${txtDireccion.text.trim()}";
                    }
                  }
                      
                  // MODIFICACIÓN CLAVE: Pasamos el flag si es recogida (modoUbicacion == 2)
                  _generarYEnviarMensaje(
                    txtNombre.text.trim(), 
                    esDelivery ? infoDireccion : null, 
                    esRecogida: (esDelivery && modoUbicacion == 2)
                  );
                },
                child: Text("Enviar Pedido", style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ),
    );
  }

  void _generarYEnviarMensaje(String nombreCliente, String? infoDireccion, {bool esRecogida = false}) async {
    // LÓGICA DE TÍTULO ACTUALIZADA
    String titulo;
    
    if (esDelivery) {
      if (esRecogida) {
        titulo = "🥡 *Para Recoger en Restaurante*"; // Mensaje específico para Takeout
      } else {
        titulo = "🛵💨 *Pedido Para Delivery*";
      }
    } else {
      titulo = "🍽️ *Pedido en Mesa*";
    }

    String mensaje = "$titulo\n\n";
    mensaje += "👤 *Cliente:* $nombreCliente\n\n";

    // Productos
    carrito.forEach((p, cant) {
      String linea = "• ${p.nombre} x$cant - RD\$${(getPrice(p) * cant).toStringAsFixed(0)}";
      
      // Agregar Nota Específica del producto (Formato WhatsApp Mejorado)
      if (notasPorProducto.containsKey(p.nombre) && notasPorProducto[p.nombre]!.isNotEmpty) {
        // Usamos negrita y un ícono de mano para que resalte
        linea += "\n  👉 *NOTA:* ${notasPorProducto[p.nombre]}";
      }
      mensaje += "$linea\n";
    });

    // Nota General
    if (_notaGeneralController.text.trim().isNotEmpty) {
      mensaje += "\n📝 *NOTA GENERAL:* ${_notaGeneralController.text.trim()}\n";
    }

    mensaje += "\n*Total de Orden: RD\$${totalCarrito.toStringAsFixed(2)}*";
    
    // Agregamos la dirección si existe
    if (infoDireccion != null && infoDireccion.isNotEmpty) {
      mensaje += "\n\n$infoDireccion";
    }

    final url = Uri.parse(
        "https://wa.me/${widget.telefonoNegocio}?text=${Uri.encodeComponent(mensaje)}");
    
    try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
           if (mounted) {
             final prefs = await SharedPreferences.getInstance();
             if(esDelivery) await _borrarDatosLocales(prefs); 
             
             Navigator.pop(context); // Cierra la pantalla de menú
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text("Abriendo WhatsApp...", style: GoogleFonts.poppins()), backgroundColor: Colors.green)
             );
          }
        } else {
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir WhatsApp")));
        }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al abrir WhatsApp")));
    }
  }

  // ---------------- UI BUILD ----------------
  @override
  Widget build(BuildContext context) {
    // ... (El build principal no cambia mucho, solo llamamos al modal actualizado)
    final Set<String> cats = productos.map((p) => p.categoria).toSet();
    final List<String> listaCategorias = ["Todas", if (productos.any((p)=>p.enOferta)) "Ofertas", ...cats];

    final ofertas = productos.where((p) => p.enOferta).toList();
    final bool mostrarCarrusel = ofertas.isNotEmpty && (categoriaSeleccionada == "Todas" || categoriaSeleccionada == "Ofertas") && filtroBusqueda.isEmpty;
    final int infiniteItemCount = _numOffers > 0 ? _maxPages : 0; 

    return Scaffold(
      backgroundColor: secondaryColor,
      appBar: AppBar(
        backgroundColor: secondaryColor,
        elevation: 0,
        scrolledUnderElevation: 2,
        iconTheme: IconThemeData(color: textWhite),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          esDelivery ? 'Menú Delivery' : 'Menú Restaurante',
          style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: () {
                   if (carrito.isNotEmpty || historialRondas.isNotEmpty) {
                     mostrarCarritoModal(context);
                   }
                 },
                child: Badge(
                  backgroundColor: accentColor,
                  isLabelVisible: carrito.isNotEmpty || historialRondas.isNotEmpty,
                  label: Text('${carrito.values.fold(0, (a, b) => a + b)}', style: const TextStyle(color: Colors.white)),
                  child: Icon(Icons.shopping_cart, color: (carrito.isNotEmpty || historialRondas.isNotEmpty) ? primaryColor : Colors.grey),
                ),
              ),
            ),
          )
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              if (estaCerrado)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    color: accentColor.withOpacity(0.2),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock, color: accentColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "⚠️ ¡CERRADO HOY! No se pueden realizar nuevos pedidos.",
                            style: GoogleFonts.poppins(color: accentColor, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Container(
                  color: secondaryColor,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    onChanged: filtrarPorTexto,
                    style: GoogleFonts.poppins(color: textWhite),
                    decoration: InputDecoration(
                      hintText: '¿Qué se te antoja hoy?',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey[600]), 
                      prefixIcon: Icon(Icons.search, color: primaryColor),
                      filled: true,
                      fillColor: cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  height: 60, 
                  color: secondaryColor,
                  child: !cargando 
                    ? ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        scrollDirection: Axis.horizontal,
                        itemCount: listaCategorias.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final cat = listaCategorias[index];
                          final isSelected = categoriaSeleccionada == cat;
                          return GestureDetector(
                            onTap: () => seleccionarCategoria(cat),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? primaryColor : cardColor,
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: isSelected 
                                  ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))]
                                  : [],
                                border: isSelected ? null : Border.all(color: Colors.white12),
                              ),
                              child: Center(
                                child: Text(
                                  cat,
                                  style: GoogleFonts.poppins(
                                    color: isSelected ? Colors.black : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : _buildSkeletonChips(), 
                ),
              ),
              if (mostrarCarrusel && !cargando)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text("🔥 Destacados", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor)),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 200,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: infiniteItemCount,
                            itemBuilder: (context, index) {
                              final actualIndex = index % ofertas.length; 
                              return _buildCarouselItem(ofertas[actualIndex]);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!cargando)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      filtroBusqueda.isNotEmpty ? "Resultados" : "Nuestro Menú :: $categoriaSeleccionada",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                    ),
                  ),
                ),
              cargando 
                  ? SliverToBoxAdapter(child: _buildSkeletonList())
                  : _buildProductListSliver(productosFiltrados),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          if (carrito.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => mostrarCarritoModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: cartColor,
                    borderRadius: BorderRadius.circular(30), 
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15)
                        ),
                        child: Text(
                          "${carrito.values.fold(0, (a, b) => a + b)}",
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Ver mi pedido",
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Text(
                        "RD\$${totalCarrito.toStringAsFixed(0)}",
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- MODAL DE CARRITO (ACTUALIZADO CON NOTAS) ---
  void mostrarCarritoModal(BuildContext context) {
    final bool isClosed = estaCerrado;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentEntries = carrito.entries.toList();

          void cerrarRonda() {
            if (carrito.isEmpty || isClosed) return;
            setState(() {
              historialRondas.add(Map.from(carrito)); 
              carrito.clear(); 
              notasPorProducto.clear();
            });
            _guardarCarrito(); 
            setModalState((){});
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Ronda guardada. Puedes pedir lo siguiente.", style: GoogleFonts.poppins()),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              )
            );
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10))),
                
                // CABECERA CON HISTORIAL
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Tu Pedido", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: textWhite)),
                          if (!esDelivery)
                            Text("Ronda Actual #${historialRondas.length + 1}", style: GoogleFonts.poppins(fontSize: 12, color: primaryColor)),
                        ],
                      ),
                      if (!esDelivery && historialRondas.isNotEmpty)
                        IconButton(
                          onPressed: () => _mostrarHistorialCompleto(context),
                          icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
                          tooltip: "Ver cuenta completa",
                          style: IconButton.styleFrom(backgroundColor: Colors.white10),
                        )
                    ],
                  ),
                ),
                
                if (isClosed && currentEntries.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    color: accentColor.withOpacity(0.3),
                    child: Text(
                      "⚠️ Está cerrado. No se puede modificar el pedido activo.",
                      style: GoogleFonts.poppins(color: accentColor, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),

                // LISTA ACTUAL
                Expanded(
                  child: currentEntries.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.room_service_outlined, size: 80, color: Colors.white10),
                            const SizedBox(height: 10),
                            Text(
                              isClosed ? "Pedido inactivo" : "Listo para pedir", 
                              style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 16)
                            ),
                          ],
                        ))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          itemCount: currentEntries.length + 1, // +1 para la nota general al final
                          separatorBuilder: (_,__) => Divider(height: 30, color: Colors.white10),
                          itemBuilder: (context, index) {
                            // --- INPUT DE NOTA GENERAL AL FINAL ---
                            if (index == currentEntries.length) {
                               return Padding(
                                 padding: const EdgeInsets.only(top: 20, bottom: 10),
                                 child: TextField(
                                   controller: _notaGeneralController,
                                   style: GoogleFonts.poppins(color: Colors.white),
                                   decoration: InputDecoration(
                                     hintText: "📝 Nota general (ej: Servilletas extra, pago con 1000...)",
                                     hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                                     filled: true,
                                     fillColor: Colors.black26,
                                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                     contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12)
                                   ),
                                 ),
                               );
                            }

                            final entry = currentEntries[index];
                            final p = entry.key;
                            final cant = carrito[p] ?? 0; 
                            if (cant == 0) return const SizedBox.shrink();

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(p.imagen, width: 60, height: 60, fit: BoxFit.cover, cacheWidth: 120),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.nombre, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: textWhite)),
                                          Text("RD\$${getPrice(p).toStringAsFixed(0)}", style: GoogleFonts.poppins(color: primaryColor, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        _btnCant(
                                          Icons.remove, 
                                          cant == 1 ? Colors.red.withOpacity(isClosed ? 0.1 : 0.2) : Colors.white.withOpacity(isClosed ? 0.05 : 0.1),
                                          cant == 1 ? Colors.red.withOpacity(isClosed ? 0.3 : 1.0) : Colors.white.withOpacity(isClosed ? 0.3 : 1.0), 
                                          isClosed ? () {} : () {
                                              gestionarCarrito(p, false);
                                              setModalState((){}); setState((){}); 
                                              if (carrito.isEmpty && historialRondas.isEmpty) Navigator.pop(context); 
                                          }
                                        ),
                                        SizedBox(width: 30, child: Center(child: Text("$cant", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: textWhite)))),
                                        _btnCant(
                                          Icons.add, 
                                          primaryColor.withOpacity(isClosed ? 0.05 : 0.2), 
                                          primaryColor.withOpacity(isClosed ? 0.3 : 1.0), 
                                          isClosed ? () {} : () {
                                              gestionarCarrito(p, true);
                                              setModalState((){}); setState((){});
                                          }
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                                // --- CAMPO DE NOTA POR PRODUCTO (MEJORADO VISUALMENTE) ---
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, left: 76), // Indentado
                                  child: Container(
                                    decoration: BoxDecoration(
                                      // Fondo amarillo suave para destacar que es una nota
                                      color: const Color(0xFFFFF9C4).withOpacity(0.1), 
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24)
                                    ),
                                    child: TextFormField(
                                      initialValue: notasPorProducto[p.nombre] ?? "",
                                      onChanged: (val) {
                                        notasPorProducto[p.nombre] = val;
                                        _guardarCarrito();
                                      },
                                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: "✍️ Agregar nota (ej: Sin cebolla)",
                                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
                                      ),
                                    ),
                                  ),
                                )
                              ],
                            );
                          },
                        ),
                ),

                // ZONA INFERIOR
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, -5))]
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Total Ronda", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: textWhite)),
                            Text("RD\$${totalCarrito.toStringAsFixed(2)}", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        if (esDelivery)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor.withOpacity(isClosed ? 0.3 : 1.0), 
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              onPressed: carrito.isNotEmpty && !isClosed ? enviarPedidoWhatsApp : null, 
                              child: Text("Confirmar Delivery 🚚", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          )
                        else
                          // MODO RESTAURANTE
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.visibility, color: Colors.white70),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text("Muestra al mesero", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                              ),
                              if (carrito.isNotEmpty)
                                TextButton.icon(
                                  onPressed: isClosed ? null : cerrarRonda,
                                  style: TextButton.styleFrom(
                                    foregroundColor: primaryColor.withOpacity(isClosed ? 0.3 : 1.0), 
                                    backgroundColor: primaryColor.withOpacity(isClosed ? 0.05 : 0.1),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                  ),
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  label: Text("Nueva Ronda", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                                )
                            ],
                          )
                      ],
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  // ... (El resto de métodos auxiliares: _mostrarHistorialCompleto, _buildCarouselItem, etc. se mantienen igual)
  
  void _mostrarHistorialCompleto(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.white),
            const SizedBox(width: 10),
            Text("Cuenta Completa", style: GoogleFonts.poppins(color: textWhite, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < historialRondas.length; i++) ...[
                  Text("Ronda #${i + 1}", style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24),
                  ...historialRondas[i].entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("${e.key.nombre} x${e.value}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13))),
                        Text("RD\$${(getPrice(e.key) * e.value).toStringAsFixed(0)}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  )),
                  const SizedBox(height: 15),
                ],
                if (carrito.isNotEmpty) ...[
                  Text("Ronda Actual (Sin cerrar)", style: GoogleFonts.poppins(color: accentColor, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24),
                  ...carrito.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("${e.key.nombre} x${e.value}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13))),
                        Text("RD\$${(getPrice(e.key) * e.value).toStringAsFixed(0)}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  )),
                ],
                const Divider(color: Colors.white, thickness: 1, height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("TOTAL A PAGAR:", style: GoogleFonts.poppins(color: textWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("RD\$${totalGeneral.toStringAsFixed(2)}", style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                )
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: const StadiumBorder()),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Volver", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  Widget _buildCarouselItem(Producto p) {
    final int currentQuantity = carrito[p] ?? 0;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              p.imagen,
              fit: BoxFit.cover,
              cacheWidth: 400, 
              errorBuilder: (_,__,___) => Container(
                color: cardColor, 
                child: Center(
                  child: Icon(Icons.broken_image, color: Colors.grey[700], size: 40),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: 15,
              left: 15,
              right: 15,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre, style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "RD\$${getPrice(p).toStringAsFixed(0)}", 
                        style: GoogleFonts.poppins(color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      GestureDetector(
                        onTap: estaCerrado ? null : () => gestionarCarrito(p, true),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0),
                                shape: BoxShape.circle
                              ),
                              child: const Icon(Icons.add, color: Colors.black, size: 20),
                            ),
                            if (currentQuantity > 0)
                              Positioned(
                                top: -5,
                                right: -5,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$currentQuantity',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
            Positioned(
              top: 15,
              right: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(20)),
                child: Text("OFERTA", style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListSliver(List<Producto> lista) {
    if (lista.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 60, color: Colors.grey[800]),
              const SizedBox(height: 10),
              Text("No encontramos productos", style: GoogleFonts.poppins(color: Colors.grey[500])),
            ],
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return _buildProductoCard(lista[index]);
        },
        childCount: lista.length,
      ),
    );
  }

  Widget _buildProductoCard(Producto p) {
    final bool isOferta = p.enOferta && p.precioOferta != null && p.precioOferta! > 0;
    final bool isJustAdded = _justAdded[p] ?? false;
    final int currentQuantity = carrito[p] ?? 0; 

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // --- FIX PARA S-PEN: Desactivar efectos de hover y focus ---
          hoverColor: Colors.transparent, 
          focusColor: Colors.transparent,
          splashColor: primaryColor.withOpacity(0.1), // Personalizar splash
          highlightColor: primaryColor.withOpacity(0.05),
          // ------------------------------------------------------------
          onTap: () => _showProductDetails(p),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: p.nombre + (isOferta ? 'list' : ''), 
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      p.imagen,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      cacheWidth: 200, 
                      errorBuilder: (_,__,___) => Container(
                        width: 100, height: 100, color: Colors.black26,
                        child: Icon(Icons.fastfood, color: Colors.grey[700]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        p.nombre,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: textWhite),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.descripcion,
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOferta ? "RD\$${p.precioOferta!.toStringAsFixed(0)}" : "RD\$${p.precio.toStringAsFixed(0)}",
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor),
                              ),
                              if (isOferta)
                                Text(
                                  "RD\$${p.precio.toStringAsFixed(0)}",
                                  style: GoogleFonts.poppins(
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: accentColor,
                                    decorationThickness: 2.0,
                                    fontSize: 11,
                                    color: Colors.grey[600]
                                  ),
                                ),
                            ],
                          ),
                          Material( 
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: estaCerrado ? null : () => gestionarCarrito(p, true),
                              child: Stack(
                                clipBehavior: Clip.none, 
                                children: [
                                  AnimatedContainer( 
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isJustAdded
                                        ? primaryColor 
                                        : Colors.white.withOpacity(estaCerrado ? 0.02 : 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                        isJustAdded ? Icons.check_rounded : Icons.add_rounded, 
                                        size: 24, 
                                        color: isJustAdded ? Colors.black : primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0)
                                    ),
                                  ),
                                  if (currentQuantity > 0)
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: accentColor, 
                                          shape: BoxShape.circle,
                                          border: Border.all(color: cardColor, width: 2) 
                                        ),
                                        child: Text(
                                          '$currentQuantity',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                ],
                              ),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonChips() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        width: 80,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSkeletonList() {
    return Column(
      children: [
        Container(
          height: 180,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
          child: Container(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20))),
        ),
        ...List.generate(3, (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 15),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 120, height: 16, color: Colors.white10),
                  const SizedBox(height: 8),
                  Container(width: 180, height: 12, color: Colors.white10),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(width: 60, height: 16, color: Colors.white10),
                    Container(width: 30, height: 30, color: Colors.white10),
                  ])
                ]),
              )
            ],
          ),
        ))
      ],
    );
  }

  Widget _btnCant(IconData icon, Color bg, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  void _showProductDetails(Producto p) {
    final bool isOferta = p.enOferta && p.precioOferta != null && p.precioOferta! > 0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9, 
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8),
                child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10))),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: p.nombre + (isOferta ? 'list' : ''), 
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
                          child: Image.network(
                            p.imagen,
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: 600, 
                            errorBuilder: (_,__,___) => Container(
                              height: 250,
                              color: Colors.black26,
                              child: const Center(child: Icon(Icons.fastfood, size: 80, color: Colors.grey)),
                            ),
                          ),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nombre,
                              style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: textWhite),
                            ),
                            const SizedBox(height: 8),
                            if (p.categoria.isNotEmpty)
                              Text(
                                p.categoria,
                                style: GoogleFonts.poppins(fontSize: 16, color: primaryColor, fontWeight: FontWeight.w600),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              p.descripcion,
                              style: GoogleFonts.poppins(fontSize: 16, height: 1.5, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              "Ingredientes / Notas de Sabor:",
                              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.ingredientes, 
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: secondaryColor,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, -5))]
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Precio:",
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500]),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "RD\$${getPrice(p).toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                              if (isOferta)
                                Text(
                                  "RD\$${p.precio.toStringAsFixed(0)}",
                                  style: GoogleFonts.poppins(
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: accentColor,
                                    decorationThickness: 2.0,
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 180,
                        child: ElevatedButton.icon(
                          onPressed: estaCerrado ? null : () {
                            gestionarCarrito(p, true);
                            Navigator.pop(context); 
                          },
                          icon: const Icon(Icons.add_shopping_cart, color: Colors.black),
                          label: Text(
                            "Añadir",
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 5,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}