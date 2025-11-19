import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:diacritic/diacritic.dart';
import 'dart:async';

String normalizar(String texto) => removeDiacritics(texto.toLowerCase());

class Producto {
  final String id;
  final String nombre;
  final String descripcion;
  final double precio;
  final double? precioOferta; 
  final String imagen;
  final String categoria;
  final String estado;
  final bool enOferta; 

  Producto({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    required this.imagen,
    required this.categoria,
    required this.estado,
    required this.enOferta,
    this.precioOferta,
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    // Manejar ID
    final id = (json['ID'] ?? json['Id'] ?? json['id'] ?? '').toString();
    // Nombre
    final nombre = (json['Nombre del Producto'] ??
            json['Nombre'] ??
            json['Producto'] ??
            '')
        .toString();
    // Descripción
    final descripcion = (json['Descripción'] ??
            json['Descripcion'] ??
            json[' descripción'] ??
            '')
        .toString();
    // Precio
    final precio =
        double.tryParse((json['Precio'] ?? json['price'] ?? '0').toString()) ??
            0.0;
    // Precio de oferta (columna EXACTA: "Precio de Oferta")
    final ofertaRaw = (json['Precio de Oferta'] ??
            json['Precio_de_Oferta'] ??
            json['precio_oferta'] ??
            json['precioOferta'] ??
            null);
    final double? precioOferta = ofertaRaw != null && ofertaRaw.toString().trim().isNotEmpty
        ? double.tryParse(ofertaRaw.toString())
        : null;
    // Imagen
    final rawImage = (json['Imagen Producto'] ??
            json['Imagen URL'] ??
            json['Imagen'] ??
            json['image'] ??
            '')
        .toString();
    final imagen = _convertirImagenAppSheet(rawImage);
    // Categoría
    final categoria =
        (json['Categoría'] ?? json['Categoria'] ?? json['category'] ?? '')
            .toString();
    // ESTADO (Disponible / Agotado)
    final estado =
        (json['Estado'] ?? json['estado'] ?? json['Estatus'] ?? '')
            .toString()
            .trim();
    // EN OFERTA - AppSheet devuelve "TRUE" / "FALSE" (texto)
    final rawEnOferta = (json['En Oferta'] ??
            json['EnOferta'] ??
            json['en_oferta'] ??
            json['enOferta'] ??
            'FALSE')
        .toString()
        .trim();
    final enOferta = rawEnOferta.toLowerCase() == 'true';

    return Producto(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      precio: precio,
      imagen: imagen,
      categoria: categoria,
      estado: estado,
      enOferta: enOferta,
      precioOferta: precioOferta,
    );
  }

  static String _convertirImagenAppSheet(String imagen) {
    final trimmed = imagen.trim();
    if (trimmed.isEmpty) return '';

    // Si ya es URL o data:
    if (trimmed.startsWith('http') || trimmed.startsWith('data:')) {
      return trimmed;
    }

    // URL AppSheet (tu appId y tableName)
    const appId = '15e7eaec-dd89-454a-9e00-13d3ee5094ed';
    const tableName = 'Productos';

    return 'https://www.appsheet.com/template/gettablefileurl?appName=$appId&tableName=$tableName&fileName=$trimmed';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Producto && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class MenuDelivery extends StatefulWidget {
  const MenuDelivery({super.key});

  @override
  State<MenuDelivery> createState() => _MenuDeliveryState();
}

class _MenuDeliveryState extends State<MenuDelivery> {
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  bool cargando = true;
  final Map<Producto, int> carrito = {};
  String filtroBusqueda = '';

  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _paginaActual = 0;
  Timer? _timer;

  // Reemplaza esta URL por tu endpoint real
  final String endpoint =
      'https://script.google.com/macros/s/AKfycbz--61eiRBC-6fZcwxOOx4EZ6e9KvT5VmrtMhv-6zUQ2hnMF18gYKP_ZYOdCF1PMqnY/exec';

  @override
  void initState() {
    super.initState();
    _cargarYConfigurar();
    _pageController.addListener(() {
      final pagina = _pageController.page?.round() ?? 0;
      if (pagina != _paginaActual) {
        setState(() {
          _paginaActual = pagina;
        });
      }
    });

    // Timer para autoplay del carrusel (solo controla page changes)
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (productosFiltrados.isEmpty) return;
      int siguiente = _paginaActual + 1;
      if (siguiente >= productosFiltrados.length) siguiente = 0;
      if (_pageController.hasClients && productosFiltrados.isNotEmpty) {
        _pageController.animateToPage(
          siguiente,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _cargarYConfigurar() async {
    await fetchProductos();
    // Asegurar que el PageController esté en una página válida
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ajustarPaginaActual();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> fetchProductos() async {
    setState(() {
      cargando = true;
    });

    try {
      final response = await http.get(Uri.parse(endpoint));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final List<Producto> parsed = data
            .map((e) => Producto.fromJson((e as Map<String, dynamic>)))
            // FILTRO: excluir filas vacías Y productos agotados
            .where((p) =>
                p.nombre.trim().isNotEmpty &&
                p.categoria.trim().isNotEmpty &&
                p.estado.toLowerCase() == 'disponible')
            .toList();

        setState(() {
          productos = parsed;

          // aplicar el filtro de búsqueda actual si existe
          if (filtroBusqueda.trim().isNotEmpty) {
            final q = normalizar(filtroBusqueda);
            productosFiltrados = productos.where((producto) {
              final nombre = normalizar(producto.nombre);
              final categoria = normalizar(producto.categoria);
              return nombre.contains(q) || categoria.contains(q);
            }).toList();
          } else {
            productosFiltrados = List.from(productos);
          }

          // Ordenar productosFiltrados para que las ofertas salgan primero en el carrusel/listados
          productosFiltrados.sort((a, b) {
            if (a.enOferta && !b.enOferta) return -1;
            if (!a.enOferta && b.enOferta) return 1;
            return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
          });

          cargando = false;
        });

        // Ajustar página actual y PageController para evitar índices fuera de rango
        _ajustarPaginaActual();
      } else {
        throw Exception('Error al cargar productos: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        cargando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar productos: $e')),
      );
    }
  }

  void _ajustarPaginaActual() {
    // Si no hay productos filtrados, resetear indice
    if (productosFiltrados.isEmpty) {
      setState(() {
        _paginaActual = 0;
      });
      return;
    }

    if (_paginaActual >= productosFiltrados.length) {
      setState(() {
        _paginaActual = productosFiltrados.length - 1;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_paginaActual);
      }
    } else {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_paginaActual);
      }
    }
  }

  void filtrarProductos(String query) {
    final filtro = normalizar(query);
    setState(() {
      filtroBusqueda = query;
      productosFiltrados = productos.where((producto) {
        final nombre = normalizar(producto.nombre);
        final categoria = normalizar(producto.categoria);
        return nombre.contains(filtro) || categoria.contains(filtro);
      }).toList();

      // Mantener orden: ofertas primero
      productosFiltrados.sort((a, b) {
        if (a.enOferta && !b.enOferta) return -1;
        if (!a.enOferta && b.enOferta) return 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    });

    // después de filtrar, garantizar página válida (ej. si lista se vacía)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ajustarPaginaActual();
    });
  }

  void agregarAlCarrito(Producto producto) {
    setState(() {
      carrito[producto] = (carrito[producto] ?? 0) + 1;
    });
  }

  void eliminarProductoDelMenu(Producto producto) {
    setState(() {
      // Quitar de listas de productos
      productos.removeWhere((p) => p.id == producto.id);
      productosFiltrados.removeWhere((p) => p.id == producto.id);
      // Quitar del carrito por si acaso
      carrito.removeWhere((k, v) => k.id == producto.id);
    });

    // Ajustar carousel si quedó sin items o índice fuera de rango
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ajustarPaginaActual();
    });
  }

  // ---------- IMPORTANT: no eliminamos producto del menú cuando se quita del carrito ----------
  void eliminarDelCarrito(Producto producto) {
    setState(() {
      if (carrito[producto] != null && carrito[producto]! > 1) {
        carrito[producto] = carrito[producto]! - 1;
      } else {
        // Solo quitar del carrito, NO eliminar del menú ni de productosFiltrados
        carrito.remove(producto);
      }
    });
  }
  // --------------------------------------------------------------------------------------------

  double getPrice(Producto p) {
    if (p.enOferta && p.precioOferta != null && p.precioOferta! > 0) {
      return p.precioOferta!;
    }
    return p.precio;
  }

  double get totalCarrito => carrito.entries
      .fold(0.0, (s, e) => s + (getPrice(e.key) * e.value));

  @override
  Widget build(BuildContext context) {
    // Generar lista de categorías y colocar "Ofertas" al principio si hay ofertas
    final List<Producto> productosEnOferta =
        productosFiltrados.where((p) => p.enOferta && p.precioOferta != null && p.precioOferta! > 0).toList();

    final categorias = <String>[];
    if (productosEnOferta.isNotEmpty) {
      categorias.add('Ofertas');
    }
    categorias.addAll(productosFiltrados
        .map((p) => p.categoria)
        .toSet()
        .where((categoria) =>
            productosFiltrados.any((p) => p.categoria == categoria))
        .toList());

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 251, 249, 245),
      appBar: AppBar(
        //cambier nombre de titulo
        title: const Text('Menú'),
        actions: [
          /*IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await fetchProductos();
            },
            tooltip: 'Refrescar desde AppSheet',
          ),*/
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () => mostrarCarrito(context),
                color: carrito.isNotEmpty
                    ? Colors.red
                    : const Color.fromARGB(255, 1, 1, 1),
              ),
              if (carrito.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red[700],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 10,
                      minHeight: 10,
                    ),
                    child: Text(
                      carrito.values.fold<int>(0, (a, b) => a + b).toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Carrusel (usa productosFiltrados para mantener coherencia con la lista)
                  SizedBox(
                    height: 240,
                    child: productosFiltrados.isEmpty
                        ? Center(
                            child: Text(
                              'No hay productos para mostrar',
                              style: TextStyle(
                                  color: Colors.brown[700],
                                  fontWeight: FontWeight.bold),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: productosFiltrados.length,
                            itemBuilder: (context, index) {
                              final producto = productosFiltrados[index];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Stack(
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 18 / 9,
                                        child: producto.imagen.isNotEmpty
                                            ? Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: Image.network(
                                                      producto.imagen,
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      errorBuilder:
                                                          (context, error, stack) =>
                                                              Container(
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                            Icons.broken_image,
                                                            size: 50),
                                                      ),
                                                    ),
                                                  ),
                                                  // etiqueta inclinada en la esquina superior izquierda si está en oferta
                                                  if (producto.enOferta && producto.precioOferta != null && producto.precioOferta! > 0)
                                                    Positioned(
                                                      top: 8,
                                                      left: -30,
                                                      child: Transform.rotate(
                                                        angle: -0.6, // inclinación
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            color: Colors.redAccent,
                                                            borderRadius: BorderRadius.circular(6),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors.black.withOpacity(0.2),
                                                                offset: const Offset(0,2),
                                                                blurRadius: 4,
                                                              ),
                                                            ],
                                                          ),
                                                          child: const Text(
                                                            '🔥 OFERTA',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              )
                                            : Container(
                                                color: Colors.grey[300],
                                                child: const Center(
                                                    child: Icon(
                                                        Icons.image_not_supported,
                                                        size: 48)),
                                              ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Colors.black.withOpacity(0.7),
                                              ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                          ),
                                          child: Text(
                                            producto.nombre,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Indicadores del carrusel
                  if (productosFiltrados.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(productosFiltrados.length, (i) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _paginaActual == i ? 14 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _paginaActual == i
                                  ? Colors.brown
                                  : Colors.brown.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),

                  // Buscador
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SizedBox(
                      width: 500,
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: 'Buscar producto o categoría',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),

                          // Bordes redondeados y desactivación del borde duro
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),

                          // Sombra suave estilo tarjeta
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                          ),
                        ),

                        onChanged: filtrarProductos,
                      ),
                    ),
                  ),
                  // Lista de categorías con pull-to-refresh
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: fetchProductos,
                      child: ListView(
                        children: categorias.map((categoria) {
                          final items = categoria == 'Ofertas'
                              ? productosFiltrados.where((p) => p.enOferta && p.precioOferta != null && p.precioOferta! > 0).toList()
                              : productosFiltrados.where((p) => p.categoria == categoria).toList();

                          if (items.isEmpty) return const SizedBox.shrink();

                          return ExpansionTile(
                            iconColor:
                                const Color.fromARGB(255, 113, 79, 67),
                            collapsedIconColor:
                                const Color.fromARGB(255, 113, 79, 67),
                            title: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                color: const Color.fromARGB(255, 113, 79, 67),
                                child: Center(
                                  child: Text(
                                    categoria.toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                ),
                              ),
                            ),
                            children: items
                                .map((producto) => Card(
                                      color: const Color(0xFFD7B899),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 9),
                                      child: ListTile(
                                        leading: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: producto.imagen.isNotEmpty
                                                  ? Image.network(
                                                      producto.imagen,
                                                      width: 80,
                                                      height: 95,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error,
                                                              stackTrace) =>
                                                          const Icon(Icons.broken_image),
                                                    )
                                                  : const Icon(Icons.image_not_supported,
                                                      size: 48),
                                            ),
                                            // etiqueta inclinada si está en oferta y tiene precio de oferta válido
                                            if (producto.enOferta && producto.precioOferta != null && producto.precioOferta! > 0)
                                              Positioned(
                                                top: 4,
                                                left: -26,
                                                child: Transform.rotate(
                                                  angle: -0.6,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.redAccent,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      '🔥 OFERTA',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        title: Text(producto.nombre),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(producto.descripcion),
                                            const SizedBox(height: 6),
                                            producto.enOferta && producto.precioOferta != null && producto.precioOferta! > 0
                                                ? Row(
                                                    children: [
                                                      Text(
                                                        'RD\$${producto.precio.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          decoration: TextDecoration.lineThrough,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'RD\$${(producto.precioOferta ?? producto.precio).toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          color: Colors.red,
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Text('RD\$${producto.precio.toStringAsFixed(2)}'),
                                          ],
                                        ),
                                        isThreeLine: true,
                                        trailing: IconButton(
                                          icon: const Icon(
                                              Icons.add_shopping_cart,
                                              color: Colors.brown),
                                          onPressed: () => agregarAlCarrito(producto),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void mostrarCarrito(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (contextModal) {
        return StatefulBuilder(
          builder: (contextModal, setStateModal) {
            void agregar(Producto producto) {
              setState(() {
                carrito[producto] = (carrito[producto] ?? 0) + 1;
              });
              setStateModal(() {});
            }

            void eliminar(Producto producto) {
              setState(() {
                if (carrito[producto] != null && carrito[producto]! > 1) {
                  carrito[producto] = carrito[producto]! - 1;
                } else {
                  // Sólo quitar del carrito, NO eliminar del menú
                  carrito.remove(producto);
                  if (carrito.isEmpty) {
                    Navigator.of(contextModal).pop();
                  }
                }
              });
              setStateModal(() {});
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Carrito 🛒',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: carrito.isEmpty
                        ? const Center(child: Text('No hay nada para ordenar'))
                        : ListView.builder(
                            itemCount: carrito.length,
                            itemBuilder: (context, index) {
                              final producto = carrito.keys.elementAt(index);
                              final cantidad = carrito[producto]!;
                              final unidad = getPrice(producto);
                              return Card(
                                color: const Color(0xFFFFFFFF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: producto.imagen.isNotEmpty
                                            ? Image.network(
                                                producto.imagen,
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    const Icon(Icons.broken_image),
                                              )
                                            : const Icon(Icons.image_not_supported,
                                                size: 60),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              producto.nombre,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text('Cantidad: $cantidad'),
                                            Text('Unidad: RD\$${unidad.toStringAsFixed(2)}'),
                                            Container(
                                              margin:
                                                  const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 3, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFDBCC),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Subtotal: RD\$${(unidad * cantidad).toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF6B4C3B),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.add, color: Colors.green),
                                            onPressed: () => agregar(producto),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.remove, color: Colors.red),
                                            onPressed: () => eliminar(producto),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFDBCC),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.brown.withOpacity(0.3),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6B4C3B)),
                          ),
                          Text(
                            'RD\$${totalCarrito.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6B4C3B)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
