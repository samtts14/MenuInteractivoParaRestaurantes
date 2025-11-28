import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'productos.dart';

// Enum para saber en qué modo estamos
enum TipoServicio { restaurante, delivery }

class UniversalMenuPage extends StatefulWidget {
  final TipoServicio tipoServicio;
  final String telefonoNegocio;

  const UniversalMenuPage({
    super.key, 
    required this.tipoServicio,
    required this.telefonoNegocio, 
  });

  @override
  State<UniversalMenuPage> createState() => _UniversalMenuPageState();
}

class _UniversalMenuPageState extends State<UniversalMenuPage> {
  // ---------------- CONFIGURACIÓN ----------------
  final String endpoint =
      'https://script.google.com/macros/s/AKfycbwr-CKWRDD0RLxbvfGnlC12wMnBJfPjwRd72YPuCI9bAZW-uHUFrv-EbqC8UJScgoWi/exec?table=Productos';
  // REMOVIDO: Se elimina la variable hardcodeada, ahora se toma de widget.telefonoNegocio

  // ---------------- ESTADO ----------------
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  String categoriaSeleccionada = "Todas";
  bool cargando = true;
  final Map<Producto, int> carrito = {}; 
  String filtroBusqueda = '';
  final Map<Producto, bool> _justAdded = {}; 

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
  
  // Usamos el Naranja para el carrito también para mantener la marca
  final cartColor = const Color(0xFFE08D00); 

  bool get esDelivery => widget.tipoServicio == TipoServicio.delivery;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    
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

  Future<void> _cargarDatos() async {
    try {
      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Producto> parsed = data
            .map((e) => Producto.fromJson(e))
            .where((p) =>
                p.nombre.isNotEmpty && p.estado.toLowerCase() == 'disponible')
            .toList();

        if (mounted) {
          setState(() {
            productos = parsed;
            _aplicarFiltros();
            cargando = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => cargando = false);
      debugPrint("Error cargando productos: $e");
    }
  }

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
    });
  }

  double getPrice(Producto p) =>
      (p.enOferta && p.precioOferta != null && p.precioOferta! > 0)
          ? p.precioOferta!
          : p.precio;

  double get totalCarrito =>
      carrito.entries.fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));

  void enviarPedidoWhatsApp() async {
    String titulo = esDelivery ? "🛵 *Pedido Para Delivery*" : "🍽️ *Pedido en Mesa*";
    String mensaje = "$titulo\n\n";

    carrito.forEach((p, cant) {
      mensaje +=
          "• ${p.nombre} x$cant - RD\$${(getPrice(p) * cant).toStringAsFixed(0)}\n";
    });

    mensaje += "\n*Total de Orden: RD\$${totalCarrito.toStringAsFixed(2)}*";

    final url = Uri.parse(
        "https://wa.me/${widget.telefonoNegocio}?text=${Uri.encodeComponent(mensaje)}");
    
    try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo abrir WhatsApp")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> cats = productos.map((p) => p.categoria).toSet();
    final List<String> listaCategorias = ["Todas", if (productos.any((p)=>p.enOferta)) "Ofertas", ...cats];

    final ofertas = productos.where((p) => p.enOferta).toList();
    final bool mostrarCarrusel = ofertas.isNotEmpty && (categoriaSeleccionada == "Todas" || categoriaSeleccionada == "Ofertas") && filtroBusqueda.isEmpty;

    return Scaffold(
      backgroundColor: secondaryColor, // FONDO NEGRO
      appBar: AppBar(
        backgroundColor: secondaryColor, // AppBar Negro
        elevation: 0,
        scrolledUnderElevation: 2,
        iconTheme: IconThemeData(color: textWhite), // Icono de atrás blanco
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          esDelivery ? 'Menú Delivery' : 'Menú Restaurante',
          style: GoogleFonts.poppins(
            color: primaryColor, // Título Naranja
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          if (carrito.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: GestureDetector(
                  onTap: () => mostrarCarritoModal(context),
                  child: Badge(
                    backgroundColor: accentColor, // Badge Rojo
                    label: Text('${carrito.values.fold(0, (a, b) => a + b)}', style: const TextStyle(color: Colors.white)),
                    child: Icon(Icons.shopping_cart, color: primaryColor), // Carrito Naranja
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
              // 1. BUSCADOR
              SliverToBoxAdapter(
                child: Container(
                  color: secondaryColor, // Fondo Negro
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    onChanged: filtrarPorTexto,
                    style: GoogleFonts.poppins(color: textWhite), // Texto al escribir blanco
                    decoration: InputDecoration(
                      hintText: '¿Qué se te antoja hoy?',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey[600]), 
                      prefixIcon: Icon(Icons.search, color: primaryColor), // Lupa Naranja
                      filled: true,
                      fillColor: cardColor, // Input Gris Oscuro
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. CHIPS DE CATEGORÍA
              SliverToBoxAdapter(
                child: Container(
                  height: 60, 
                  color: secondaryColor, // Fondo Negro
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
                                color: isSelected ? primaryColor : cardColor, // Naranja o Gris Oscuro
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: isSelected 
                                  ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))]
                                  : [],
                                border: isSelected ? null : Border.all(color: Colors.white12), // Borde sutil si no está seleccionado
                              ),
                              child: Center(
                                child: Text(
                                  cat,
                                  style: GoogleFonts.poppins(
                                    color: isSelected ? Colors.black : Colors.white70, // Texto negro sobre naranja, blanco sobre gris
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
                          child: Text("🔥 Destacados", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor)), // Rojo Fuego
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
              // 4. TÍTULO DE LISTA
                if (!cargando)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        filtroBusqueda.isNotEmpty 
                            ? "Resultados" 
                            : "Nuestro Menú :: ${categoriaSeleccionada}", // Muestra la categoría seleccionada
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor), // Naranja
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

          // 6. BARRA FLOTANTE DEL CARRITO
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
                    color: cartColor, // Naranja
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
                          color: Colors.black.withOpacity(0.2), // Oscurecer un poco sobre el naranja
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

  // --- WIDGET: Ítem del Carrusel ---
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
              errorBuilder: (_,__,___) => Container(
                color: cardColor, 
                child: Center(
                  child: Icon(Icons.broken_image, color: Colors.grey[700], size: 40),
                ),
              ),
            ),
            // Degradado para leer texto
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
            // Info
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
                        style: GoogleFonts.poppins(color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold), // Precio Naranja
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                        child: const Icon(Icons.add, color: Colors.white, size: 20),
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
                decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(20)), // Etiqueta Roja
                child: Text("OFERTA", style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET: Lista Sliver ---
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

  // --- WIDGET: TARJETA DE PRODUCTO (OSCURA) ---
  Widget _buildProductoCard(Producto p) {
    final bool isOferta = p.enOferta && p.precioOferta != null && p.precioOferta! > 0;
    final bool isJustAdded = _justAdded[p] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor, // Tarjeta Gris Oscuro
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)), // Borde muy sutil
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
                      cacheWidth: 250, 
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
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor), // Precio Naranja
                              ),
                              if (isOferta)
                                Text(
                                  "RD\$${p.precio.toStringAsFixed(0)}",
                                  // --- CAMBIO AQUI ---
                                  style: GoogleFonts.poppins(
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: accentColor, // <--- COLOR ROJO EN EL TACHADO
                                      decorationThickness: 2.0,     // <--- GROSOR DE LA LÍNEA
                                      fontSize: 11,
                                      color: Colors.grey[600]
                                  ),
                                  // -------------------
                                ),
                            ],
                          ),
                          // Botón Agregar
                          Material( 
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => gestionarCarrito(p, true), 
                              child: AnimatedContainer( 
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isJustAdded ? primaryColor : Colors.white.withOpacity(0.05), // Botón inactivo es gris casi transparente
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isJustAdded ? Icons.check_rounded : Icons.add_rounded, 
                                  size: 24, 
                                  color: isJustAdded ? Colors.black : primaryColor // Icono Naranja
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

  // --- SKELETONS PARA CARGA (OSCUROS) ---
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

  // --- MODAL DETALLES DEL PRODUCTO (OSCURO) ---
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
            color: cardColor, // Fondo Modal Gris Oscuro
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
                      // IMAGEN
                      Hero(
                        tag: p.nombre + (isOferta ? 'list' : ''), 
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
                          child: Image.network(
                            p.imagen,
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_,__,___) => Container(
                              height: 250,
                              color: Colors.black26,
                              child: const Center(child: Icon(Icons.fastfood, size: 80, color: Colors.grey)),
                            ),
                          ),
                        ),
                      ),
                      
                      // DETALLES DEL TEXTO
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
                              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor), // Rojo
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

              // BARRA INFERIOR (OSCURA)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: secondaryColor, // Fondo Negro
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
                                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor), // Naranja
                              ),
                              if (isOferta)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Text(
                                    "RD\$${p.precio.toStringAsFixed(0)}",
                                    // --- CAMBIO AQUI ---
                                    style: GoogleFonts.poppins(
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: accentColor, // <--- COLOR ROJO
                                      decorationThickness: 2.0,     // <--- GROSOR
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                    // -------------------
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      
                      // Botón Añadir Modal
                      SizedBox(
                        width: 180,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            gestionarCarrito(p, true);
                            Navigator.pop(context); 
                          },
                          icon: const Icon(Icons.add_shopping_cart, color: Colors.black), // Icono Negro
                          label: Text(
                            "Añadir",
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black), // Texto Negro para contraste con Naranja
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor, // Naranja
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

  // --- MODAL CARRITO (OSCURO) ---
  void mostrarCarritoModal(BuildContext context) {
    final carritoEntries = carrito.entries.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentEntries = carrito.entries.toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: cardColor, // Fondo Modal Gris Oscuro
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10))),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Tu Pedido", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: textWhite)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, size: 28, color: textWhite))
                    ],
                  ),
                ),
                Expanded(
                  child: currentEntries.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_basket_outlined, size: 80, color: Colors.white10),
                            const SizedBox(height: 10),
                            Text("Tu carrito está vacío 😔", style: GoogleFonts.poppins(color: Colors.grey[500])),
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
                                      cant == 1 ? Colors.red.withOpacity(0.2) : Colors.white10,
                                      cant == 1 ? Colors.red : Colors.white, 
                                      () {
                                        gestionarCarrito(p, false);
                                        setModalState((){}); 
                                        setState((){}); 
                                        if (carrito.isEmpty) Navigator.pop(context); 
                                      }
                                    ),
                                    SizedBox(
                                      width: 30, 
                                      child: Center(
                                        child: Text("$cant", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: textWhite))
                                      )
                                    ),
                                    _btnCant(
                                      Icons.add, 
                                      primaryColor.withOpacity(0.2), // Fondo Naranja suave
                                      primaryColor, // Icono Naranja
                                      () {
                                        gestionarCarrito(p, true);
                                        setModalState((){});
                                        setState((){});
                                      }
                                    ),
                                  ],
                                )
                              ],
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: secondaryColor, // Fondo Negro
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, -5))]
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Total", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: textWhite)),
                            Text("RD\$${totalCarrito.toStringAsFixed(2)}", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (esDelivery)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor, // Botón Confirmar ROJO
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              onPressed: carrito.isNotEmpty ? enviarPedidoWhatsApp : null,
                              child: Text(
                                "Confirmar Delivery 🛵",
                                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: primaryColor, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Un mesero tomará tu orden en breve.",
                                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
                                  ),
                                ),
                              ],
                            ),
                          ),
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