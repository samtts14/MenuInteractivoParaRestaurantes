import 'package:diacritic/diacritic.dart';

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
    final id = (json['ID'] ?? json['Id'] ?? json['id'] ?? '').toString();
    final nombre = (json['Nombre del Producto'] ?? json['Nombre'] ?? json['Producto'] ?? '').toString();
    final descripcion = (json['Descripción'] ?? json['Descripcion'] ?? '').toString();
    
    final precio = double.tryParse((json['Precio'] ?? json['price'] ?? '0').toString()) ?? 0.0;
    
    final ofertaRaw = (json['Precio de Oferta'] ?? json['precio_oferta'] ?? null);
    final double? precioOferta = ofertaRaw != null && ofertaRaw.toString().trim().isNotEmpty
        ? double.tryParse(ofertaRaw.toString())
        : null;

    final rawImage = (json['Imagen Producto'] ?? json['Imagen'] ?? '').toString();
    final imagen = _convertirImagenAppSheet(rawImage);

    final categoria = (json['Categoría'] ?? json['Categoria'] ?? '').toString();
    final estado = (json['Estado'] ?? json['estado'] ?? '').toString().trim();
    
    final rawEnOferta = (json['En Oferta'] ?? 'FALSE').toString().trim();
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
    if (trimmed.startsWith('http') || trimmed.startsWith('data:')) return trimmed;

    // TUS CREDENCIALES
    const appId = '15e7eaec-dd89-454a-9e00-13d3ee5094ed';
    const tableName = 'Productos';

    return 'https://www.appsheet.com/template/gettablefileurl?appName=$appId&tableName=$tableName&fileName=$trimmed';
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is Producto && id == other.id;

  @override
  int get hashCode => id.hashCode;
}