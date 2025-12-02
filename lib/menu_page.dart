import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'productos.dart';

// Enum para saber en qu\u00e9 modo estamos
enum TipoServicio { restaurante, delivery }

class UniversalMenuPage extends StatefulWidget {
  final TipoServicio tipoServicio;
  final String telefonoNegocio;
  // PROPIEDAD AGREGADA: Recibe el estado de si el negocio est\u00e1 abierto hoy.
  final bool estaAbierto; 

  const UniversalMenuPage({
    super.key, 
    required this.tipoServicio,
    required this.telefonoNegocio,
    required this.estaAbierto, // A\u00d1ADIDO AL CONSTRUCTOR
  });

  @override
  State<UniversalMenuPage> createState() => _UniversalMenuPageState();
}

class _UniversalMenuPageState extends State<UniversalMenuPage> {
  // ---------------- CONFIGURACI\u00d3N ----------------
  final String endpoint =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec?table=Productos';
  
  // ---------------- ESTADO ----------------
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  String categoriaSeleccionada = "Todas";
  bool cargando = true;
  String filtroBusqueda = '';
  final Map<Producto, bool> _justAdded = {}; 

  // CARRITO Y HISTORIAL DE RONDAS
  final Map<Producto, int> carrito = {}; 
  List<Map<Producto, int>> historialRondas = []; // Lista de mapas para guardar las rondas pasadas

  // Variables para el Carrusel
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _paginaActual = 0;
  Timer? _timer;

  // ---------------- COLORES DE LA MARCA (PARMESANO DARK) ----------------
  final primaryColor = const Color(0xFFE08D00); // Naranja Mostaza
  final secondaryColor = const Color(0xFF000000); // Negro Puro (Fondo)
  final cardColor = const Color(0xFF1E1E1E); // Gris Oscuro (Tarjetas)
  final accentColor = const Color(0xFFE53935); // Rojo (Ofertas/Acentos)
  final textWhite = const Color(0xFFFFFFFF); // Blanco
  final cartColor = const Color(0xFFE08D00); 

  bool get esDelivery => widget.tipoServicio == TipoServicio.delivery;
  // Acceso al estado de apertura
  bool get estaAbierto => widget.estaAbierto; 
  bool get estaCerrado => !widget.estaAbierto; 


  @override
  void initState() {
    super.initState();
    _cargarProductos(); // Carga directa del men\u00fa (sin cach\u00e9 de productos para velocidad)
    
    _pageController.addListener(() {
      int next = _pageController.page?.round() ?? 0;
      if (_paginaActual != next) {
        setState(() => _paginaActual = next);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (productos.where((p) => p.enOferta).isEmpty) return;
      if (_pageController.hasClients) {
        int siguiente = _paginaActual + 1;
        if (siguiente >= productos.where((p) => p.enOferta).length) {
          siguiente = 0;
          _pageController.jumpToPage(0); 
        } else {
          _pageController.animateToPage(
            siguiente,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ---------------- PERSISTENCIA INTELIGENTE (CARRITO SI, MEN\u00da NO) ----------------
  // Mantenemos SharedPreferences SOLO para el carrito y el historial, para que no se pierda al refrescar.

  Future<void> _guardarCarrito() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Convertir Carrito Actual a JSON
    final Map<String, int> carritoSimple = {};
    carrito.forEach((p, c) => carritoSimple[p.nombre] = c);
    
    // 2. Convertir Historial a JSON
    final List<Map<String, int>> historialSimple = historialRondas.map((ronda) {
      final Map<String, int> rondaMap = {};
      ronda.forEach((p, c) => rondaMap[p.nombre] = c);
      return rondaMap;
    }).toList();

    await prefs.setString('carrito_persistente', jsonEncode(carritoSimple));
    await prefs.setString('historial_persistente', jsonEncode(historialSimple));

    // 3. Gestionar el Tiempo de Vida (5 HORAS)
    // Guardamos la hora de inicio solo si es la primera vez que se guarda algo.
    if (!prefs.containsKey('hora_inicio_orden')) {
      await prefs.setString('hora_inicio_orden', DateTime.now().toIso8601String());
    }
  }

  Future<void> _restaurarCarrito(List<Producto> productosReferencia) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // --- VERIFICACI\u00d3N DE CADUCIDAD (5 HORAS) ---
      final String? horaInicioStr = prefs.getString('hora_inicio_orden');
      
      if (horaInicioStr != null) {
        final DateTime horaInicio = DateTime.parse(horaInicioStr);
        final DateTime ahora = DateTime.now();
        final Duration diferencia = ahora.difference(horaInicio);

        // Si han pasado m\u00e1s de 5 horas, BORRAMOS TODO autom\u00e1ticamente
        if (diferencia.inHours >= 5) {
          debugPrint("La sesi\u00f3n de 5 horas caduc\u00f3. Limpiando datos...");
          await _borrarDatosLocales(prefs);
          return; // Salimos, no restauramos nada
        }
      }
      // ------------------------------------------

      // 1. Cargar Carrito Actual (Si existe y no ha caducado)
      final String? carritoJson = prefs.getString('carrito_persistente');
      if (carritoJson != null) {
        final Map<String, dynamic> datos = jsonDecode(carritoJson);
        final Map<Producto, int> restaurado = {};
        datos.forEach((nom, cant) {
            try {
              // Buscamos el producto en la lista reci\u00e9n cargada
              final p = productosReferencia.firstWhere((element) => element.nombre == nom);
              restaurado[p] = cant as int;
            } catch (_) {}
        });
        if (mounted) setState(() { carrito.clear(); carrito.addAll(restaurado); });
      }

      // 2. Cargar Historial de Rondas
      final String? historialJson = prefs.getString('historial_persistente');
      if (historialJson != null) {
        final List<dynamic> listaRondas = jsonDecode(historialJson);
        final List<Map<Producto, int>> historialRestaurado = [];

        for (var ronda in listaRondas) {
          final Map<String, dynamic> rondaMap = ronda;
          final Map<Producto, int> rondaObj = {};
          rondaMap.forEach((nom, cant) {
            try {
              final p = productosReferencia.firstWhere((element) => element.nombre == nom);
              rondaObj[p] = cant as int;
            } catch (_) {}
          });
          if (rondaObj.isNotEmpty) historialRestaurado.add(rondaObj);
        }
        if (mounted) setState(() => historialRondas = historialRestaurado);
      }
    } catch (e) {
      debugPrint("Error restaurando carrito: $e");
    }
  }

  Future<void> _borrarDatosLocales(SharedPreferences prefs) async {
    await prefs.remove('carrito_persistente');
    await prefs.remove('historial_persistente');
    await prefs.remove('hora_inicio_orden');
    if (mounted) {
      setState(() {
        carrito.clear();
        historialRondas.clear();
      });
    }
  }

  // ---------------- CARGA DE DATOS (DIRECTA - SIN CACH\u00c9 DE MEN\u00da) ----------------
  Future<void> _cargarProductos() async {
    try {
      // Solicitud directa a internet para asegurar datos frescos y evitar cach\u00e9 corrupto
      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Producto> listaFresca = _parsearProductos(data);

        if (mounted) {
          setState(() {
            productos = listaFresca;
            _aplicarFiltros();
            cargando = false;
          });
          // Una vez tenemos los productos frescos, restauramos el carrito guardado
          _restaurarCarrito(listaFresca); 
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
        .where((p) => p.nombre.isNotEmpty && p.estado.toLowerCase() == 'disponible')
        .toList();
  }

  // ---------------- L\u00d3GICA DE NEGOCIO ----------------

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

  void gestionarCarrito(Producto p, bool agregar) {
    // REGLA: No se puede modificar el carrito si el negocio est\u00e1 cerrado
    if (estaCerrado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("El negocio est\u00e1 cerrado, no se pueden a\u00f1adir o eliminar items.", style: GoogleFonts.poppins()), backgroundColor: accentColor)
      );
      return;
    }

    setState(() {
      if (agregar) {
        carrito[p] = (carrito[p] ?? 0) + 1;
        _justAdded[p] = true;
        Timer(const Duration(milliseconds: 700), () {
          if (mounted) {
            setState(() {
              _justAdded.remove(p);
            });
          }
        });
      } else {
        if (carrito[p] != null && carrito[p]! > 1) {
          carrito[p] = carrito[p]! - 1;
        } else {
          carrito.remove(p);
        }
      }
      _guardarCarrito(); // Guardamos cada cambio en el carrito
    });
  }

  double getPrice(Producto p) =>
      (p.enOferta && p.precioOferta != null && p.precioOferta! > 0)
          ? p.precioOferta!
          : p.precio;

  double get totalCarrito =>
      carrito.entries.fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));
  
  // Total que suma el carrito actual + todas las rondas anteriores
  double get totalGeneral {
    double total = totalCarrito;
    for (var ronda in historialRondas) {
      total += ronda.entries.fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));
    }
    return total;
  }

  void enviarPedidoWhatsApp() async {
    if (estaCerrado) return; // Doble chequeo

    String titulo = esDelivery ? "\uD83D\uDEA4 *Pedido Para Delivery*" : "\uD83C\uDF7D\uFE0F *Pedido en Mesa*";
    String mensaje = "$titulo\n\n";

    carrito.forEach((p, cant) {
      mensaje +=
          "\u2022 ${p.nombre} x$cant - RD\$${(getPrice(p) * cant).toStringAsFixed(0)}\n";
    });

    mensaje += "\n*Total de Orden: RD\$${totalCarrito.toStringAsFixed(2)}*";

    final url = Uri.parse(
        "https://wa.me/${widget.telefonoNegocio}?text=${Uri.encodeComponent(mensaje)}");
    
    try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
           if (mounted) {
             final prefs = await SharedPreferences.getInstance();
             await _borrarDatosLocales(prefs); // En delivery se borra todo al enviar
             Navigator.pop(context);
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text("Pedido Enviado", style: GoogleFonts.poppins()), backgroundColor: Colors.green)
             );
          }
        }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al abrir WhatsApp")));
    }
  }

  // ---------------- UI BUILD ----------------
  @override
  Widget build(BuildContext context) {
    final Set<String> cats = productos.map((p) => p.categoria).toSet();
    final List<String> listaCategorias = ["Todas", if (productos.any((p)=>p.enOferta)) "Ofertas", ...cats];

    final ofertas = productos.where((p) => p.enOferta).toList();
    final bool mostrarCarrusel = ofertas.isNotEmpty && (categoriaSeleccionada == "Todas" || categoriaSeleccionada == "Ofertas") && filtroBusqueda.isEmpty;

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
          esDelivery ? 'Men\u00fa Delivery' : 'Men\u00fa Restaurante',
          style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          // Icono Carrito Flotante (AppBar)
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
              // BARRA DE ADVERTENCIA DE CIERRE (Nueva)
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
                            "\u26A0\uFE0F \u00a1CERRADO HOY! No se pueden realizar nuevos pedidos.",
                            style: GoogleFonts.poppins(color: accentColor, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
              // 1. BUSCADOR
              SliverToBoxAdapter(
                child: Container(
                  color: secondaryColor,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    onChanged: filtrarPorTexto,
                    style: GoogleFonts.poppins(color: textWhite),
                    decoration: InputDecoration(
                      hintText: '\u00bfQu\u00e9 se te antoja hoy?',
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

              // 2. CHIPS DE CATEGOR\u00cdA
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

              // 3. CARRUSEL DE OFERTAS
              if (mostrarCarrusel && !cargando)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text("\uD83D\uDD25 Destacados", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor)),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 200,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: ofertas.length,
                            itemBuilder: (context, index) {
                              return _buildCarouselItem(ofertas[index]);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // 4. T\u00cdTULO DE LISTA
              if (!cargando)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter( // CORREGIDO: 'slivers' cambiado a 'sliver'
                    child: Text(
                      filtroBusqueda.isNotEmpty ? "Resultados" : "Nuestro Men\u00fa :: $categoriaSeleccionada",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                    ),
                  ),
                ),

              // 5. LISTA DE PRODUCTOS
              cargando 
                  ? SliverToBoxAdapter(child: _buildSkeletonList())
                  : _buildProductListSliver(productosFiltrados),
              
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // 6. BARRA FLOTANTE DEL CARRITO (Solo si hay items activos)
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

  // --- MODAL DE CARRITO (L\u00d3GICA DE RONDAS) ---
  void mostrarCarritoModal(BuildContext context) {
    final bool isClosed = estaCerrado; // Alias para simplificar

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentEntries = carrito.entries.toList();

          // L\u00d3GICA: CERRAR RONDA (Mover al historial)
          void cerrarRonda() {
            if (carrito.isEmpty || isClosed) return; // Chequeo de cerrado
            setState(() {
              historialRondas.add(Map.from(carrito)); // Mover a historial
              carrito.clear(); // Limpiar activo
            });
            _guardarCarrito(); // Guardar el cambio
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
            height: MediaQuery.of(context).size.height * 0.85,
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
                      
                      // BOT\u00d3N VER CUENTA COMPLETA (Icono de Recibo)
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
                
                // MENSAJE DE CERRADO EN EL CARRITO
                if (isClosed && currentEntries.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    color: accentColor.withOpacity(0.3),
                    child: Text(
                      "\u26A0\uFE0F Est\u00e1 cerrado. No se puede modificar el pedido activo.",
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
                              isClosed ? "Pedido inactivo (Negocio cerrado)" : "Listo para la siguiente ronda", 
                              style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 16)
                            ),
                            if (historialRondas.isNotEmpty)
                               Text("Tienes ${historialRondas.length} rondas anteriores guardadas.", style: GoogleFonts.poppins(color: primaryColor, fontSize: 12)),
                          ],
                        ))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: currentEntries.length, 
                          separatorBuilder: (_,__) => Divider(height: 30, color: Colors.white10),
                          itemBuilder: (context, index) {
                            final entry = currentEntries[index];
                            final p = entry.key;
                            final cant = carrito[p] ?? 0; 
                            if (cant == 0) return const SizedBox.shrink();

                            return Row(
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
                                      cant == 1 ? Colors.red.withOpacity(isClosed ? 0.1 : 0.2) : Colors.white.withOpacity(isClosed ? 0.05 : 0.1), // Deshabilitado visualmente
                                      cant == 1 ? Colors.red.withOpacity(isClosed ? 0.3 : 1.0) : Colors.white.withOpacity(isClosed ? 0.3 : 1.0), 
                                      isClosed ? () {} : () { // Deshabilitado por l\u00f3gica
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
                                      isClosed ? () {} : () { // Deshabilitado por l\u00f3gica
                                          gestionarCarrito(p, true);
                                          setModalState((){}); setState((){});
                                        }
                                      ),
                                  ],
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
                                backgroundColor: accentColor.withOpacity(isClosed ? 0.3 : 1.0), // Deshabilitado visual
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              onPressed: carrito.isNotEmpty && !isClosed ? enviarPedidoWhatsApp : null, // Deshabilitado por l\u00f3gica
                              child: Text("Confirmar Delivery \uD83D\uDEA4", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          )
                        else
                          // MODO RESTAURANTE - Bot\u00f3n "Nueva Ronda"
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
                                  onPressed: isClosed ? null : cerrarRonda, // Deshabilitado por l\u00f3gica
                                  style: TextButton.styleFrom(
                                    foregroundColor: primaryColor.withOpacity(isClosed ? 0.3 : 1.0), // Deshabilitado visual
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

  // --- MODAL DE HISTORIAL COMPLETO (RECIBO) ---
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
                // 1. Mostrar Rondas Anteriores
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

                // 2. Mostrar Ronda Actual (si hay algo)
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

  // --- WIDGETS AUXILIARES ---

  Widget _buildCarouselItem(Producto p) {
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
                        onTap: estaCerrado ? null : () => gestionarCarrito(p, true), // Deshabilitado si est\u00e1 cerrado
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0), // Deshabilitado visual
                            shape: BoxShape.circle
                          ),
                          child: const Icon(Icons.add, color: Colors.black, size: 20),
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
                              onTap: estaCerrado ? null : () => gestionarCarrito(p, true), // Deshabilitado si est\u00e1 cerrado
                              child: AnimatedContainer( 
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isJustAdded 
                                    ? primaryColor 
                                    : Colors.white.withOpacity(estaCerrado ? 0.02 : 0.05), // Deshabilitado visual
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isJustAdded ? Icons.check_rounded : Icons.add_rounded, 
                                  size: 24, 
                                  color: isJustAdded ? Colors.black : primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0) // Deshabilitado visual
                                ),
                              ),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
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
                          Row(
                            children: [
                              Text(
                                "RD\$${getPrice(p).toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                              if (isOferta)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Text(
                                    "RD\$${p.precio.toStringAsFixed(0)}",
                                    style: GoogleFonts.poppins(
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: accentColor,
                                      decorationThickness: 2.0,
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      
                      SizedBox(
                        width: 180,
                        child: ElevatedButton.icon(
                          onPressed: estaCerrado ? null : () { // Deshabilitado si est\u00e1 cerrado
                            gestionarCarrito(p, true);
                            Navigator.pop(context); 
                          },
                          icon: const Icon(Icons.add_shopping_cart, color: Colors.black),
                          label: Text(
                            "A\u00f1adir",
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor.withOpacity(estaCerrado ? 0.3 : 1.0), // Deshabilitado visual
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
}