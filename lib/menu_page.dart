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

  const UniversalMenuPage({super.key, required this.tipoServicio});

  @override
  State<UniversalMenuPage> createState() => _UniversalMenuPageState();
}

class _UniversalMenuPageState extends State<UniversalMenuPage> {
  // ---------------- CONFIGURACIÓN ----------------
  final String endpoint =
      'https://script.google.com/macros/s/AKfycbz59V25BN0CUM0z3aecZ7WZK8iRRYiZ3vJf2dnKXU5E5hZEypUjj1Ugj9y6UrzgmCuc/exec?table=Productos';
  final String telefonoNegocio = "8293474922";

  // ---------------- ESTADO ----------------
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  String categoriaSeleccionada = "Todas";
  bool cargando = true;
  final Map<Producto, int> carrito = {};
  String filtroBusqueda = '';

  // Variables para el Carrusel
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _paginaActual = 0;
  Timer? _timer;

  // ---------------- COLORES DE LA MARCA ----------------
  final primaryColor = const Color(0xFF8C5A3A); // Café Migajas
  final secondaryColor = const Color(0xFFF2E8DC); // Crema
  final accentColor = const Color(0xFF3E2723); // Café oscuro
  final cartColor = const Color(0xFF2E7D32); // Verde

  bool get esDelivery => widget.tipoServicio == TipoServicio.delivery;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    
    // Listener para actualizar el indicador del carrusel
    _pageController.addListener(() {
      int next = _pageController.page?.round() ?? 0;
      if (_paginaActual != next) {
        setState(() => _paginaActual = next);
      }
    });

    // Auto-scroll del carrusel cada 5 segundos
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (productos.where((p) => p.enOferta).isEmpty) return;
      if (_pageController.hasClients) {
        int siguiente = _paginaActual + 1;
        if (siguiente >= productos.where((p) => p.enOferta).length) {
          siguiente = 0;
          _pageController.jumpToPage(0); // Volver al inicio sin animación brusca al final
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

    // Ordenar: Ofertas primero
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
    String titulo = esDelivery ? "🛵 *Pedido Delivery*" : "🍽️ *Pedido en Mesa*";
    String mensaje = "$titulo\n\n";

    carrito.forEach((p, cant) {
      mensaje +=
          "• ${p.nombre} x$cant - RD\$${(getPrice(p) * cant).toStringAsFixed(0)}\n";
    });

    mensaje += "\n*Total: RD\$${totalCarrito.toStringAsFixed(2)}*";

    if (esDelivery) {
      mensaje += "\n\n📍 *Dirección de entrega:* (Escribir aquí)";
      mensaje += "\n📍 *Ubicación:* (Enviar ubicación)";
    } else {
      mensaje += "\n\n🪑 *Mesa:* (Indicar número)";
    }

    final url = Uri.parse(
        "https://wa.me/$telefonoNegocio?text=${Uri.encodeComponent(mensaje)}");
    
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
    // Lista de categorías para los chips
    final Set<String> cats = productos.map((p) => p.categoria).toSet();
    final List<String> listaCategorias = ["Todas", if (productos.any((p)=>p.enOferta)) "Ofertas", ...cats];

    // Productos en oferta para el carrusel
    final ofertas = productos.where((p) => p.enOferta).toList();
    final bool mostrarCarrusel = ofertas.isNotEmpty && (categoriaSeleccionada == "Todas" || categoriaSeleccionada == "Ofertas") && filtroBusqueda.isEmpty;

    return Scaffold(
      backgroundColor: secondaryColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          esDelivery ? 'Menú Delivery' : 'Menú Restaurante',
          style: GoogleFonts.poppins(
            color: primaryColor,
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
                child: Badge(
                  backgroundColor: Colors.red,
                  label: Text('${carrito.values.fold(0, (a, b) => a + b)}'),
                  child: Icon(Icons.shopping_cart, color: primaryColor),
                ),
              ),
            )
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. BUSCADOR (Fijo arriba en la lista, pero scrollea con el contenido)
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    onChanged: filtrarPorTexto,
                    style: GoogleFonts.poppins(),
                    decoration: InputDecoration(
                      hintText: '¿Qué se te antoja hoy?',
                      hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[100],
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
                  height: 60, // Altura fija para los chips
                  color: Colors.white,
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
                                color: isSelected ? primaryColor : Colors.grey[100],
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: isSelected 
                                  ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))]
                                  : [],
                              ),
                              child: Center(
                                child: Text(
                                  cat,
                                  style: GoogleFonts.poppins(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : _buildSkeletonChips(), // Skeleton para chips
                ),
              ),

              // 3. CARRUSEL DE OFERTAS (Visible si hay ofertas y no está filtrado)
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

              // 4. TÍTULO DE LISTA (Opcional, para separar)
              if (!cargando)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      filtroBusqueda.isNotEmpty ? "Resultados" : "Nuestro Menú",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor),
                    ),
                  ),
                ),

              // 5. LISTA DE PRODUCTOS (SliverList para rendimiento)
              cargando 
                  ? SliverToBoxAdapter(child: _buildSkeletonList())
                  : _buildProductListSliver(productosFiltrados),
              
              // Espacio final para el carrito flotante
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
                    color: cartColor,
                    borderRadius: BorderRadius.circular(30), // Más redondeado
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 8))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 5))
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
              errorBuilder: (_,__,___) => Container(color: Colors.grey[300], child: const Icon(Icons.fastfood, color: Colors.grey)),
            ),
            // Degradado para leer texto
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
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
                        "RD\$${p.precioOferta!.toStringAsFixed(0)}",
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(Icons.add, color: primaryColor, size: 20),
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
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                child: Text("OFERTA", style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET: Lista Sliver (Para rendimiento con muchos items) ---
  Widget _buildProductListSliver(List<Producto> lista) {
    if (lista.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
              const SizedBox(height: 10),
              Text("No encontramos productos", style: GoogleFonts.poppins(color: Colors.grey)),
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

  // --- WIDGET: TARJETA DE PRODUCTO (Estilo Llamativo) ---
  Widget _buildProductoCard(Producto p) {
    final bool isOferta = p.enOferta && p.precioOferta != null && p.precioOferta! > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => gestionarCarrito(p, true),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen con caché y bordes redondeados
                Hero(
                  tag: p.nombre + (isOferta ? 'list' : ''), // Tag único si es posible
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      p.imagen,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      cacheWidth: 250, 
                      errorBuilder: (_,__,___) => Container(
                        width: 100, height: 100, color: Colors.grey[100], 
                        child: Icon(Icons.fastfood, color: Colors.grey[300]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                // Información
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        p.nombre,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.descripcion,
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
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
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: isOferta ? Colors.red[700] : primaryColor),
                              ),
                              if (isOferta)
                                Text(
                                  "RD\$${p.precio.toStringAsFixed(0)}",
                                  style: GoogleFonts.poppins(decoration: TextDecoration.lineThrough, fontSize: 11, color: Colors.grey[400]),
                                ),
                            ],
                          ),
                          // Botón Agregar más llamativo
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: secondaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.add_rounded, size: 24, color: primaryColor),
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

  // --- SKELETONS PARA CARGA ---
  Widget _buildSkeletonChips() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        width: 80,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSkeletonList() {
    return Column(
      children: [
        // Skeleton Carrusel
        Container(
          height: 180,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Container(decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20))),
        ),
        // Skeleton Items
        ...List.generate(3, (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 15),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 120, height: 16, color: Colors.grey[100]),
                  const SizedBox(height: 8),
                  Container(width: 180, height: 12, color: Colors.grey[100]),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(width: 60, height: 16, color: Colors.grey[100]),
                    Container(width: 30, height: 30, color: Colors.grey[100]),
                  ])
                ]),
              )
            ],
          ),
        ))
      ],
    );
  }

  // --- MODAL CARRITO (Mismo estilo funcional) ---
  void mostrarCarritoModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Tu Pedido", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 28))
                    ],
                  ),
                ),
                Expanded(
                  child: carrito.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_basket_outlined, size: 80, color: Colors.grey[200]),
                            const SizedBox(height: 10),
                            Text("Tu carrito está vacío 😔", style: GoogleFonts.poppins(color: Colors.grey)),
                          ],
                        ))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: carrito.length,
                          separatorBuilder: (_,__) => const Divider(height: 30),
                          itemBuilder: (context, index) {
                            final p = carrito.keys.elementAt(index);
                            final cant = carrito[p]!;
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
                                      Text(p.nombre, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                                      Text("RD\$${getPrice(p).toStringAsFixed(0)}", style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    _btnCant(Icons.remove, cant == 1 ? Colors.red[50]! : Colors.grey[100]!, cant == 1 ? Colors.red : Colors.black87, () {
                                      gestionarCarrito(p, false);
                                      setModalState((){});
                                      setState((){});
                                      if (carrito.isEmpty) Navigator.pop(context);
                                    }),
                                    SizedBox(width: 30, child: Center(child: Text("$cant", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)))),
                                    _btnCant(Icons.add, Colors.green[50]!, Colors.green[700]!, () {
                                      gestionarCarrito(p, true);
                                      setModalState((){});
                                      setState((){});
                                    }),
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
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Total", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text("RD\$${totalCarrito.toStringAsFixed(2)}", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cartColor,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: carrito.isNotEmpty ? enviarPedidoWhatsApp : null,
                            child: Text(
                              esDelivery ? "Confirmar Dirección 🛵" : "Enviar a Cocina 👨‍🍳",
                              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
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