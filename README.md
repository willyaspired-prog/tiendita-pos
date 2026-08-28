# Tiendita POS

Aplicación de punto de venta minimal para una tiendita de abarrotes, desarrollada en Python (Tkinter) y SQLite. La aplicación incluye: venta con carrito, gestión de productos, inventario, apertura/cierre de turno (arqueo de caja), registro de gastos, gestión de usuarios, exportar ventas a CSV, backup automático de la base de datos y generación básica de ticket de texto.

Contenido del repositorio:
- main.py  -> código fuente principal (self-contained, no librerías externas)
- build_exe.bat -> script para generar TienditaPOS.exe con PyInstaller
- README.md -> instrucciones de uso
- .github/workflows/build.yml -> workflow para compilar el exe en GitHub Actions
- .gitignore -> archivos/dirs a ignorar

Recomendaciones previas:
- El ejecutable se puede generar con PyInstaller en Windows.
- La base de datos (tienda.db) se creará en la misma carpeta donde se ejecute el .exe o main.py.
- Usuario por defecto: admin / admin (cámbialo en producción).

Licencia: MIT
