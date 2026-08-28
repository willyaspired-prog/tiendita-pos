#!/usr/bin/env bash
set -euo pipefail

# create_and_push.sh
# Ejecuta en la raíz del repo (o donde quieres inicializarlo). 
# Asegúrate de tener credenciales para push (SSH/HTTPS).

ROOT_DIR="$(pwd)"
echo "Working dir: $ROOT_DIR"

# Check for git repo
if [ ! -d ".git" ]; then
  echo "No veo un repositorio git en esta carpeta."
  read -p "¿Quieres inicializar uno aquí? (y/N): " doinit
  if [[ "$doinit" =~ ^[Yy]$ ]]; then
    git init
    echo "Repositorio git inicializado."
  else
    echo "Por favor clona el repo willyaspired-prog/tiendita-pos y ejecuta este script allí."
    exit 1
  fi
fi

# Ensure branch (use current branch)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Rama actual: $CURRENT_BRANCH"

# Create directories
mkdir -p .github/workflows
mkdir -p backups

# Write README.md
cat > README.md <<'README'
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
README

# Write .gitignore
cat > .gitignore <<'GITIGNORE'
# Byte-compiled / distribution folders
__pycache__/
*.pyc
*.pyo
*.pyd
build/
dist/
*.spec
*.egg-info/
venv/
.env
*.db
*.sqlite
*.log
GITIGNORE

# Write LICENSE (MIT)
cat > LICENSE <<'LICENSE'
MIT License

Copyright (c) 2026 willyaspired-prog

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSE

# Write build_exe.bat
cat > build_exe.bat <<'BAT'
@echo off
REM Empaqueta main.py en un solo .exe (Windows) con PyInstaller
REM Ejecutar en CMD. Recomendado crear y usar un virtualenv.

REM 1) Crear y activar virtualenv (opcional)
REM python -m venv venv
REM venv\Scripts\activate

REM 2) Instalar PyInstaller
pip install pyinstaller

REM 3) Generar EXE (ventana sin consola)
pyinstaller --onefile --windowed --name TienditaPOS main.py

echo Terminado. El ejecutable estará en dist\TienditaPOS.exe
pause
BAT

# Write GitHub Actions workflow
cat > .github/workflows/build.yml <<'YML'
name: Build TienditaPOS

on:
  push:
    branches: [ main ]
  workflow_dispatch: {}

jobs:
  build:
    runs-on: windows-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install PyInstaller
        run: |
          python -m pip install --upgrade pip
          pip install pyinstaller

      - name: Build executable with PyInstaller
        run: |
          pyinstaller --onefile --windowed --name TienditaPOS main.py

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: TienditaPOS-exe
          path: dist/TienditaPOS.exe
YML

# Write main.py (contenido completo)
cat > main.py <<'PY'
# main.py - Tiendita POS completo (versión ampliada)
# Requisitos: Python 3.8+ (sin paquetes externos)
import os
import sys
import sqlite3
import hashlib
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog
from datetime import datetime
import shutil
import csv

# --- Rutas ---
def app_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

DB_PATH = os.path.join(app_dir(), "tienda.db")
BACKUP_DIR = os.path.join(app_dir(), "backups")
os.makedirs(BACKUP_DIR, exist_ok=True)

# --- Esquema DB ampliado ---
DB_SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sku TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT,
  cost REAL NOT NULL DEFAULT 0,
  price REAL NOT NULL DEFAULT 0,
  min_stock INTEGER NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  password_hash TEXT,
  role TEXT
);

CREATE TABLE IF NOT EXISTS cash_shifts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user TEXT,
  start_time TEXT,
  end_time TEXT,
  start_cash REAL,
  end_cash REAL,
  total_sales REAL,
  total_expenses REAL,
  closed INTEGER DEFAULT 0,
  note TEXT
);

CREATE TABLE IF NOT EXISTS sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  total REAL NOT NULL,
  total_cost REAL NOT NULL,
  cash_received REAL,
  change REAL,
  user TEXT,
  shift_id INTEGER,
  discount REAL DEFAULT 0,
  tax REAL DEFAULT 0,
  FOREIGN KEY(shift_id) REFERENCES cash_shifts(id)
);

CREATE TABLE IF NOT EXISTS sale_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sale_id INTEGER NOT NULL,
  product_id INTEGER,
  sku TEXT,
  name TEXT,
  quantity INTEGER,
  unit_price REAL,
  subtotal REAL,
  profit REAL,
  FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE,
  FOREIGN KEY(product_id) REFERENCES products(id)
);

CREATE TABLE IF NOT EXISTS inventory_movements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER,
  date TEXT,
  type TEXT,
  qty INTEGER,
  note TEXT,
  user TEXT,
  FOREIGN KEY(product_id) REFERENCES products(id)
);

CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT,
  category TEXT,
  amount REAL,
  description TEXT,
  receipt_path TEXT,
  user TEXT,
  shift_id INTEGER,
  FOREIGN KEY(shift_id) REFERENCES cash_shifts(id)
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
"""

# --- Inicialización DB ---
def init_db():
    created = not os.path.exists(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.executescript(DB_SCHEMA)
    # usuario admin por defecto
    cur.execute("SELECT COUNT(*) FROM users")
    if cur.fetchone()[0] == 0:
        pw = hashlib.sha256("admin".encode()).hexdigest()
        cur.execute("INSERT INTO users(username,password_hash,role) VALUES (?,?,?)",
                    ("admin", pw, "admin"))
    # setting por defecto tax_rate si no existe
    cur.execute("SELECT value FROM settings WHERE key='tax_rate'")
    if not cur.fetchone():
        cur.execute("INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)", ("tax_rate", "0.00"))
    conn.commit()
    conn.close()
    if created:
        print("Base de datos creada en:", DB_PATH)

# --- Utilidades de usuario ---
def hash_pw(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

def verify_user(username, password):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("SELECT password_hash, role FROM users WHERE username=?", (username,))
        r = cur.fetchone()
        if not r: return None
        pw_hash, role = r
        if pw_hash == hash_pw(password):
            return role
    return None

def create_user(username, password, role="cajero"):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        try:
            cur.execute("INSERT INTO users(username,password_hash,role) VALUES (?,?,?)",
                        (username, hash_pw(password), role))
            conn.commit()
            return True
        except sqlite3.IntegrityError:
            return False

# --- Productos / inventario ---
def search_products(term=""):
    q = "SELECT id, sku, name, price, stock FROM products WHERE 1=1"
    params = []
    if term:
        q += " AND (sku LIKE ? OR name LIKE ?)"
        params += [f"%{term}%", f"%{term}%"]
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute(q, params)
        return cur.fetchall()

def get_product_by_id(pid):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("SELECT id, sku, name, price, cost, stock FROM products WHERE id=?", (pid,))
        return cur.fetchone()

# --- Movimientos y ventas ---
def create_sale(items, cash_received, user="admin", shift_id=None, discount_pct=0.0, tax_rate=0.0):
    total_items = round(sum(it['subtotal'] for it in items), 2)
    discount_amount = round(total_items * (discount_pct/100.0), 2)
    taxed_base = total_items - discount_amount
    tax_amount = round(taxed_base * tax_rate, 2)
    total = round(taxed_base + tax_amount, 2)
    total_cost = round(sum(it['quantity'] * it['cost'] for it in items), 2)
    change = round(cash_received - total, 2)
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("""INSERT INTO sales(date,total,total_cost,cash_received,change,user,shift_id,discount,tax)
                       VALUES (?,?,?,?,?,?,?,?,?)""",
                    (datetime.now().isoformat(), total, total_cost, cash_received, change, user, shift_id, discount_pct, tax_amount))
        sale_id = cur.lastrowid
        for it in items:
            profit = round((it['unit_price'] - it['cost']) * it['quantity'], 2)
            cur.execute("""INSERT INTO sale_items(sale_id,product_id,sku,name,quantity,unit_price,subtotal,profit)
                           VALUES (?,?,?,?,?,?,?,?)""",
                        (sale_id, it['product_id'], it['sku'], it['name'], it['quantity'], it['unit_price'], it['subtotal'], profit))
            # reducir stock
            cur.execute("UPDATE products SET stock = stock - ? WHERE id=?", (it['quantity'], it['product_id']))
            cur.execute("INSERT INTO inventory_movements(product_id,date,type,qty,note,user) VALUES (?,?,?,?,?)",
                        (it['product_id'], datetime.now().isoformat(), "SALE", -it['quantity'], f"Venta #{sale_id}", user))
        conn.commit()
    return sale_id, change, total, discount_amount, tax_amount

# --- Turnos / Arqueo de caja ---
def start_shift(user, start_cash):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("INSERT INTO cash_shifts(user,start_time,start_cash,closed) VALUES (?,?,?,0)",
                    (user, datetime.now().isoformat(), start_cash))
        conn.commit()
        return cur.lastrowid

def close_shift(shift_id, end_cash, note=""):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        # obtener start_time
        cur.execute("SELECT start_time,user FROM cash_shifts WHERE id=?", (shift_id,))
        r = cur.fetchone()
        if not r:
            return False
        start_time, user = r
        # calcular totales
        cur.execute("SELECT COALESCE(SUM(total),0) FROM sales WHERE shift_id=?",(shift_id,))
        total_sales = float(cur.fetchone()[0] or 0.0)
        cur.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE shift_id=?",(shift_id,))
        total_expenses = float(cur.fetchone()[0] or 0.0)
        cur.execute("UPDATE cash_shifts SET end_time=?, end_cash=?, total_sales=?, total_expenses=?, closed=1, note=? WHERE id=?",
                    (datetime.now().isoformat(), end_cash, total_sales, total_expenses, note, shift_id))
        conn.commit()
        return {"shift_id": shift_id, "user": user, "total_sales": total_sales, "total_expenses": total_expenses}

# --- Gastos ---
def register_expense(category, amount, description, user, shift_id=None, receipt_path=None):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("INSERT INTO expenses(date,category,amount,description,receipt_path,user,shift_id) VALUES (?,?,?,?,?,?,?)",
                    (datetime.now().isoformat(), category, amount, description, receipt_path, user, shift_id))
        conn.commit()
        return cur.lastrowid

# --- Settings ---
def get_setting(key, default=None):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("SELECT value FROM settings WHERE key=?", (key,))
        r = cur.fetchone()
        return r[0] if r else default

def set_setting(key, value):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)", (key, str(value)))
        conn.commit()

# --- Backups ---
def backup_db():
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = os.path.join(BACKUP_DIR, f"tienda_backup_{ts}.db")
    shutil.copy2(DB_PATH, dest)
    return dest

# --- Export CSV ventas ---
def export_sales_csv(start_date, end_date, dest_path):
    # start_date and end_date are strings in ISO format or partial; use LIKE
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("""SELECT id,date,total,total_cost,cash_received,change,user,discount,tax FROM sales
                       WHERE date BETWEEN ? AND ? ORDER BY date""", (start_date, end_date))
        rows = cur.fetchall()
    with open(dest_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id","date","total","total_cost","cash_received","change","user","discount_pct","tax_amount"])
        writer.writerows(rows)
    return dest_path

# --- Ticket (impresión básica en Windows: os.startfile(path,'print')) ---
def generate_ticket_text(sale_id):
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cur.execute("SELECT date,total,user,discount,tax FROM sales WHERE id=?", (sale_id,))
        sale = cur.fetchone()
        cur.execute("SELECT sku,name,quantity,unit_price,subtotal FROM sale_items WHERE sale_id=?", (sale_id,))
        items = cur.fetchall()
    if not sale: return None
    date, total, user, discount_pct, tax_amount = sale
    lines = []
    lines.append("TIENDITA - TICKET")
    lines.append(f"Venta: {sale_id}    Fecha: {date}")
    lines.append(f"Cajero: {user}")
    lines.append("-"*32)
    for sku,name,qty,unit,subtotal in items:
        lines.append(f"{sku} {name}")
        lines.append(f"  {qty} x {unit:.2f} = {subtotal:.2f}")
    lines.append("-"*32)
    lines.append(f"Descuento: {discount_pct}%")
    lines.append(f"IVA: {tax_amount:.2f}")
    lines.append(f"TOTAL: {total:.2f}")
    lines.append("-"*32)
    lines.append("Gracias por su compra")
    return "\n".join(lines)

def print_ticket(sale_id):
    text = generate_ticket_text(sale_id)
    if not text:
        return False, "Venta no encontrada"
    fname = os.path.join(app_dir(), f"ticket_{sale_id}.txt")
    with open(fname, "w", encoding="utf-8") as f:
        f.write(text)
    # intentar enviar a impresora (Windows)
    try:
        if sys.platform.startswith("win"):
            os.startfile(fname, "print")
            return True, fname
    except Exception as e:
        return False, f"Error impresión automática: {e}. Ticket guardado en: {fname}"
    return True, fname

# --- UI ---
class LoginWindow(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Login - Tiendita POS")
        self.geometry("360x180")
        ttk.Label(self, text="Usuario:").pack(pady=(12,0))
        self.entry_user = ttk.Entry(self); self.entry_user.pack(pady=4)
        ttk.Label(self, text="Contraseña:").pack()
        self.entry_pw = ttk.Entry(self, show="*"); self.entry_pw.pack(pady=4)
        ttk.Button(self, text="Entrar", command=self.try_login).pack(pady=8)
        ttk.Button(self, text="Backup DB", command=self.do_backup).pack(pady=(0,6))
        self.bind("<Return>", lambda e: self.try_login())

    def try_login(self):
        u = self.entry_user.get().strip()
        p = self.entry_pw.get().strip()
        if not u or not p:
            messagebox.showwarning("Faltan datos", "Ingrese usuario y contraseña.")
            return
        role = verify_user(u, p)
        if role:
            self.destroy()
            app = POSApp(user=u, role=role)
            app.mainloop()
        else:
            messagebox.showerror("Acceso denegado", "Usuario o contraseña incorrectos.")

    def do_backup(self):
        dest = backup_db()
        messagebox.showinfo("Backup creado", f"Backup creado en:\n{dest}")

class POSApp(tk.Tk):
    def __init__(self, user, role):
        super().__init__()
        self.user = user
        self.role = role
        self.current_shift = None  # store shift_id if opened
        self.title(f"Tiendita POS - Usuario: {user} ({role})")
        self.geometry("960x660")
        # Menú
        menubar = tk.Menu(self)
        filemenu = tk.Menu(menubar, tearoff=0)
        filemenu.add_command(label="Backup DB", command=self.menu_backup)
        filemenu.add_command(label="Exportar ventas (CSV)", command=self.menu_export_sales)
        filemenu.add_separator()
        filemenu.add_command(label="Salir", command=self.quit)
        menubar.add_cascade(label="Archivo", menu=filemenu)

        adm = tk.Menu(menubar, tearoff=0)
        adm.add_command(label="Usuarios", command=self.open_user_mgmt)
        adm.add_command(label="Configuración", command=self.open_settings)
        menubar.add_cascade(label="Admin", menu=adm)

        turno = tk.Menu(menubar, tearoff=0)
        turno.add_command(label="Abrir Turno", command=self.open_shift_dialog)
        turno.add_command(label="Cerrar Turno", command=self.close_shift_dialog)
        menubar.add_cascade(label="Turno", menu=turno)

        self.config(menu=menubar)

        # Top frame search / controls
        top = ttk.Frame(self); top.pack(fill=tk.X, padx=8, pady=6)
        ttk.Label(top, text="Buscar SKU/Nombre:").pack(side=tk.LEFT)
        self.entry_search = ttk.Entry(top, width=36); self.entry_search.pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Buscar", command=self.on_search).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Productos", command=self.open_products).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Historial", command=self.open_history).pack(side=tk.LEFT, padx=6)
        ttk.Label(top, text=f"Turno:").pack(side=tk.RIGHT)
        self.lbl_shift = ttk.Label(top, text="No abierto")
        self.lbl_shift.pack(side=tk.RIGHT, padx=8)

        # Products tree
        cols = ("id","sku","name","price","stock")
        self.tree_products = ttk.Treeview(self, columns=cols, show="headings", height=8)
        for c,h,w in [("id","ID",50),("sku","SKU",120),("name","Producto",420),("price","P.V.",90),("stock","Stock",90)]:
            self.tree_products.heading(c, text=h); self.tree_products.column(c, width=w)
        self.tree_products.pack(fill=tk.X, padx=8)
        self.tree_products.bind("<Double-1>", self.add_selected_to_cart)

        # Cart
        ttk.Label(self, text="Carrito:").pack(anchor=tk.W, padx=8, pady=(8,0))
        cart_cols = ("sku","name","qty","unit","subtotal")
        self.cart_tree = ttk.Treeview(self, columns=cart_cols, show="headings", height=10)
        for c,h,w in [("sku","SKU",120),("name","Producto",400),("qty","Cantidad",80),("unit","P.Unit",100),("subtotal","Subtotal",120)]:
            self.cart_tree.heading(c, text=h); self.cart_tree.column(c, width=w)
        self.cart_tree.pack(fill=tk.X, padx=8)
        ctrl = ttk.Frame(self); ctrl.pack(fill=tk.X, padx=8, pady=6)
        ttk.Button(ctrl, text="Eliminar Item", command=self.remove_item).pack(side=tk.LEFT)
        ttk.Button(ctrl, text="Vaciar Carrito", command=self.clear_cart).pack(side=tk.LEFT, padx=6)
        ttk.Button(ctrl, text="Registrar Gasto", command=self.open_expense_dialog).pack(side=tk.LEFT, padx=6)
        ttk.Button(ctrl, text="Cobrar", command=self.checkout).pack(side=tk.RIGHT)
        self.lbl_total = ttk.Label(self, text="Total: 0.00", font=("Segoe UI", 12, "bold")); self.lbl_total.pack(anchor=tk.E, padx=10)
        self.cart = []
        self.on_search()
        self.update_shift_label()

        # Apply role restrictions UI
        if self.role != "admin":
            # disable admin menu entries for non-admin
            adm.entryconfig("Usuarios", state="disabled")
            adm.entryconfig("Configuración", state="disabled")

    def menu_backup(self):
        dest = backup_db()
        messagebox.showinfo("Backup creado", f"Backup creado en:\n{dest}")

    def menu_export_sales(self):
        # ask date range
        start = simpledialog.askstring("Exportar ventas", "Fecha inicio (YYYY-MM-DD) (incluye):", initialvalue=datetime.now().strftime("%Y-%m-01"), parent=self)
        if not start: return
        end = simpledialog.askstring("Exportar ventas", "Fecha fin (YYYY-MM-DD) (incluye):", initialvalue=datetime.now().strftime("%Y-%m-%d"), parent=self)
        if not end: return
        start_iso = start + "T00:00:00"
        end_iso = end + "T23:59:59"
        dest = filedialog.asksaveasfilename(defaultextension=".csv", filetypes=[("CSV","*.csv")], title="Guardar CSV")
        if not dest: return
        export_sales_csv(start_iso, end_iso, dest)
        messagebox.showinfo("Exportado", f"Ventas exportadas a:\n{dest}")

    def open_user_mgmt(self):
        if self.role != "admin":
            messagebox.showwarning("Permiso denegado", "Solo administradores pueden gestionar usuarios.")
            return
        UserMgmtWindow(self)

    def open_settings(self):
        if self.role != "admin":
            messagebox.showwarning("Permiso denegado", "Solo administradores pueden acceder a configuración.")
            return
        SettingsWindow(self)

    def open_shift_dialog(self):
        if self.current_shift:
            messagebox.showinfo("Turno", "Ya tienes un turno abierto.")
            return
        start_cash = simpledialog.askfloat("Abrir turno", "Monto inicial de caja:", minvalue=0.0, initialvalue=0.0, parent=self)
        if start_cash is None: return
        sid = start_shift(self.user, start_cash)
        self.current_shift = sid
        self.update_shift_label()
        messagebox.showinfo("Turno abierto", f"Turno #{sid} abierto con {start_cash:.2f}")

    def close_shift_dialog(self):
        if not self.current_shift:
            messagebox.showwarning("Sin turno", "No hay turno abierto.")
            return
        end_cash = simpledialog.askfloat("Cerrar turno", "Monto en caja al cierre:", minvalue=0.0, initialvalue=0.0, parent=self)
        if end_cash is None: return
        note = simpledialog.askstring("Nota", "Observación (opcional):", parent=self) or ""
        res = close_shift(self.current_shift, end_cash, note)
        if res:
            messagebox.showinfo("Turno cerrado", f"Turno cerrado. Ventas: {res['total_sales']:.2f}, Gastos: {res['total_expenses']:.2f}")
            self.current_shift = None
            self.update_shift_label()
        else:
            messagebox.showerror("Error", "No fue posible cerrar el turno.")

    def update_shift_label(self):
        if self.current_shift:
            self.lbl_shift.config(text=f"#{self.current_shift} (abierto)")
        else:
            self.lbl_shift.config(text="No abierto")

    def on_search(self):
        term = self.entry_search.get().strip()
        rows = search_products(term)
        for r in self.tree_products.get_children(): self.tree_products.delete(r)
        for row in rows:
            self.tree_products.insert("", tk.END, values=row)

    def add_selected_to_cart(self, event=None):
        sel = self.tree_products.selection()
        if not sel: return
        vals = self.tree_products.item(sel[0])['values']
        pid, sku, name, price, stock = vals
        qty = simpledialog.askinteger("Cantidad", f"Ingrese cantidad para {name} (Stock: {stock})", minvalue=1, initialvalue=1, parent=self)
        if qty is None: return
        prod = get_product_by_id(pid)
        if not prod:
            messagebox.showerror("Error", "Producto no encontrado.")
            return
        _, sku, name, unit_price, cost, stock = prod
        if qty > stock:
            if not messagebox.askyesno("Stock insuficiente", f"Stock actual {stock}. ¿Deseas continuar?"):
                return
        subtotal = round(qty * unit_price, 2)
        item = {"product_id": pid, "sku": sku, "name": name, "quantity": qty, "unit_price": unit_price, "subtotal": subtotal, "cost": cost}
        self.cart.append(item)
        self.refresh_cart()

    def refresh_cart(self):
        for r in self.cart_tree.get_children(): self.cart_tree.delete(r)
        total = 0
        for it in self.cart:
            self.cart_tree.insert("", tk.END, values=(it['sku'], it['name'], it['quantity'], f"{it['unit_price']:.2f}", f"{it['subtotal']:.2f}"))
            total += it['subtotal']
        self.lbl_total.config(text=f"Total: {total:.2f}")

    def remove_item(self):
        sel = self.cart_tree.selection()
        if not sel: return
        idx = self.cart_tree.index(sel[0])
        del self.cart[idx]
        self.refresh_cart()

    def clear_cart(self):
        if messagebox.askyesno("Confirmar", "Vaciar carrito?"):
            self.cart = []
            self.refresh_cart()

    def checkout(self):
        if not self.cart:
            messagebox.showwarning("Carrito vacío", "Agrega productos antes de cobrar.")
            return
        total_items = round(sum(it['subtotal'] for it in self.cart), 2)
        discount_pct = simpledialog.askfloat("Descuento", "Descuento (%) sobre total:", minvalue=0.0, maxvalue=100.0, initialvalue=0.0, parent=self)
        if discount_pct is None:
            return
        tax_rate = float(get_setting("tax_rate", "0.00") or 0.0)
        # tax_rate stored as decimal (e.g., 0.16)
        cash_needed_preview = round((total_items - (total_items*(discount_pct/100.0))) * (1 + tax_rate), 2)
        cash = simpledialog.askfloat("Cobrar", f"Total (aplicado): {cash_needed_preview:.2f}\nIngresa monto recibido:", minvalue=0.0, initialvalue=cash_needed_preview, parent=self)
        if cash is None: return
        if cash < cash_needed_preview:
            messagebox.showwarning("Pago insuficiente", "El monto recibido es menor al total.")
            return
        sale_id, change, total, disc_amt, tax_amt = create_sale(self.cart, cash, user=self.user, shift_id=self.current_shift, discount_pct=discount_pct, tax_rate=tax_rate)
        ok, info = print_ticket(sale_id)
        if ok:
            messagebox.showinfo("Venta registrada", f"Venta #{sale_id}\nCambio: {change:.2f}\nTicket: {info}")
        else:
            messagebox.showinfo("Venta registrada", f"Venta #{sale_id}\nCambio: {change:.2f}\n{info}")
        self.cart = []
        self.refresh_cart()
        self.on_search()

    def open_products(self):
        ProductsWindow(self)

    def open_history(self):
        HistoryWindow(self, role=self.role)

    def open_expense_dialog(self):
        ExpenseDialog(self, user=self.user, shift_id=self.current_shift)

class ProductsWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title("Productos")
        self.geometry("760x460")
        cols = ("id","sku","name","price","stock","min_stock")
        self.tree = ttk.Treeview(self, columns=cols, show="headings")
        for c,h,w in [("id","ID",50),("sku","SKU",120),("name","Nombre",300),("price","P.V.",80),("stock","Stock",80),("min_stock","Min",80)]:
            self.tree.heading(c,text=h); self.tree.column(c,width=w)
        self.tree.pack(fill=tk.BOTH, expand=True)
        btns = ttk.Frame(self); btns.pack(fill=tk.X, pady=6)
        ttk.Button(btns, text="Nuevo", command=self.new_product).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Editar", command=self.edit_product).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Eliminar", command=self.delete_product).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Ajustar Stock", command=self.adjust_stock).pack(side=tk.LEFT, padx=6)
        self.refresh()

    def refresh(self):
        for r in self.tree.get_children(): self.tree.delete(r)
        rows = search_products()
        for r in rows:
            pid,sku,name,price,stock = r
            self.tree.insert("", tk.END, values=(pid,sku,name,f"{price:.2f}",stock,0))

    def new_product(self):
        dlg = ProductDialog(self)
        self.wait_window(dlg)
        if getattr(dlg, "saved", False): self.refresh()

    def edit_product(self):
        sel = self.tree.selection()
        if not sel: return
        pid = self.tree.item(sel[0])['values'][0]
        dlg = ProductDialog(self, pid)
        self.wait_window(dlg)
        if getattr(dlg, "saved", False): self.refresh()

    def delete_product(self):
        sel = self.tree.selection()
        if not sel: return
        pid = self.tree.item(sel[0])['values'][0]
        if messagebox.askyesno("Confirmar","Eliminar producto?"):
            with sqlite3.connect(DB_PATH) as conn:
                conn.execute("DELETE FROM products WHERE id=?", (pid,))
                conn.commit()
            self.refresh()

    def adjust_stock(self):
        sel = self.tree.selection()
        if not sel: return
        pid = self.tree.item(sel[0])['values'][0]
        qty = simpledialog.askinteger("Ajustar Stock", "Ingresa cantidad (+/-):", parent=self)
        if qty is None: return
        note = simpledialog.askstring("Nota", "Descripción del ajuste (opcional):", parent=self) or "Ajuste manual"
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("UPDATE products SET stock = stock + ? WHERE id=?", (qty, pid))
            cur.execute("INSERT INTO inventory_movements(product_id,date,type,qty,note,user) VALUES (?,?,?,?,?)",
                        (pid, datetime.now().isoformat(), "ADJUSTMENT", qty, note, "admin"))
            conn.commit()
        self.refresh()
        messagebox.showinfo("Listo", "Stock actualizado.")

class ProductDialog(tk.Toplevel):
    def __init__(self, parent, product_id=None):
        super().__init__(parent)
        self.product_id = product_id
        self.saved = False
        self.title("Producto")
        self.geometry("420x420")
        fields = [("SKU",""),("Nombre",""),("Descripción",""),("Categoría",""),("Costo","0"),("Precio","0"),("Min Stock","0"),("Stock","0")]
        self.entries = {}
        for label, default in fields:
            ttk.Label(self, text=label).pack(anchor=tk.W, padx=8, pady=(6,0))
            e = ttk.Entry(self); e.pack(fill=tk.X, padx=8)
            e.insert(0, default)
            self.entries[label] = e
        if product_id:
            with sqlite3.connect(DB_PATH) as conn:
                cur = conn.cursor()
                cur.execute("SELECT sku,name,description,category,cost,price,min_stock,stock FROM products WHERE id=?", (product_id,))
                r = cur.fetchone()
                if r:
                    keys = ["SKU","Nombre","Descripción","Categoría","Costo","Precio","Min Stock","Stock"]
                    for val,k in zip(r, keys):
                        self.entries[k].delete(0, tk.END)
                        self.entries[k].insert(0, str(val))
        ttk.Button(self, text="Guardar", command=self.save).pack(pady=12)

    def save(self):
        try:
            sku = self.entries["SKU"].get().strip()
            name = self.entries["Nombre"].get().strip()
            desc = self.entries["Descripción"].get().strip()
            cat = self.entries["Categoría"].get().strip()
            cost = float(self.entries["Costo"].get() or 0)
            price = float(self.entries["Precio"].get() or 0)
            min_stock = int(self.entries["Min Stock"].get() or 0)
            stock = int(self.entries["Stock"].get() or 0)
        except Exception as e:
            messagebox.showerror("Error", f"Valores inválidos: {e}")
            return
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            if self.product_id:
                cur.execute("""UPDATE products SET sku=?,name=?,description=?,category=?,cost=?,price=?,min_stock=?,stock=? WHERE id=?""",
                            (sku, name, desc, cat, cost, price, min_stock, stock, self.product_id))
            else:
                try:
                    cur.execute("""INSERT INTO products(sku,name,description,category,cost,price,min_stock,stock) VALUES (?,?,?,?,?,?,?,?)""",
                                (sku, name, desc, cat, cost, price, min_stock, stock))
                except sqlite3.IntegrityError:
                    messagebox.showerror("Error", "SKU ya existe.")
                    return
            conn.commit()
        self.saved = True
        self.destroy()

class ExpenseDialog(tk.Toplevel):
    def __init__(self, parent, user, shift_id=None):
        super().__init__(parent)
        self.user = user
        self.shift_id = shift_id
        self.title("Registrar Gasto")
        self.geometry("360x260")
        ttk.Label(self, text="Categoría:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.combo_cat = ttk.Combobox(self, values=["Luz","Agua","Alquiler","Internet","Otros"]); self.combo_cat.pack(fill=tk.X, padx=8)
        ttk.Label(self, text="Monto:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.entry_amount = ttk.Entry(self); self.entry_amount.pack(fill=tk.X, padx=8)
        ttk.Label(self, text="Descripción:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.entry_desc = ttk.Entry(self); self.entry_desc.pack(fill=tk.X, padx=8)
        ttk.Button(self, text="Registrar", command=self.save).pack(pady=12)

    def save(self):
        try:
            amount = float(self.entry_amount.get())
        except:
            messagebox.showerror("Error","Monto inválido")
            return
        cat = self.combo_cat.get() or "Otros"
        desc = self.entry_desc.get().strip()
        register_expense(cat, amount, desc, self.user, shift_id=self.shift_id)
        messagebox.showinfo("Listo","Gasto registrado")
        self.destroy()

class HistoryWindow(tk.Toplevel):
    def __init__(self, parent, role="cajero"):
        super().__init__(parent)
        self.role = role
        self.title("Historial de ventas")
        self.geometry("860x480")
        cols = ("id","date","total","user","discount","tax")
        self.tree = ttk.Treeview(self, columns=cols, show="headings")
        for c,h,w in [("id","ID",80),("date","Fecha",300),("total","Total",120),("user","Usuario",120),("discount","Desc(%)",80),("tax","IVA",80)]:
            self.tree.heading(c,h); self.tree.column(c,width=w)
        self.tree.pack(fill=tk.BOTH, expand=True)
        btns = ttk.Frame(self); btns.pack(fill=tk.X)
        ttk.Button(btns, text="Refrescar", command=self.refresh).pack(side=tk.LEFT, padx=6, pady=6)
        ttk.Button(btns, text="Imprimir ticket", command=self.imprimir_selected).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Exportar CSV (fecha)", command=self.export_by_date).pack(side=tk.LEFT, padx=6)
        self.refresh()

    def refresh(self):
        for r in self.tree.get_children(): self.tree.delete(r)
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("SELECT id,date,total,user,discount,tax FROM sales ORDER BY id DESC LIMIT 500")
            for row in cur.fetchall():
                self.tree.insert("", tk.END, values=(row[0], row[1], f"{row[2]:.2f}", row[3] or "", f"{row[4]:.2f}", f"{row[5]:.2f}"))

    def imprimir_selected(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showwarning("Seleccione", "Seleccione una venta")
            return
        sale_id = self.tree.item(sel[0])['values'][0]
        ok, info = print_ticket(sale_id)
        if ok:
            messagebox.showinfo("Impresión", f"Ticket enviado/guardado: {info}")
        else:
            messagebox.showerror("Error", info)

    def export_by_date(self):
        start = simpledialog.askstring("Exportar", "Fecha inicio (YYYY-MM-DD):", parent=self)
        if not start: return
        end = simpledialog.askstring("Exportar", "Fecha fin (YYYY-MM-DD):", parent=self)
        if not end: return
        start_iso = start + "T00:00:00"; end_iso = end + "T23:59:59"
        dest = filedialog.asksaveasfilename(defaultextension=".csv", filetypes=[("CSV","*.csv")])
        if not dest: return
        export_sales_csv(start_iso, end_iso, dest)
        messagebox.showinfo("Exportado", f"Exportado a {dest}")

class UserMgmtWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title("Gestión de usuarios")
        self.geometry("460x360")
        self.tree = ttk.Treeview(self, columns=("id","username","role"), show="headings")
        for c,h,w in [("id","ID",80),("username","Usuario",200),("role","Role",120)]:
            self.tree.heading(c,h); self.tree.column(c,width=w)
        self.tree.pack(fill=tk.BOTH, expand=True)
        btns = ttk.Frame(self); btns.pack(fill=tk.X)
        ttk.Button(btns, text="Nuevo", command=self.new_user).pack(side=tk.LEFT, padx=6, pady=6)
        ttk.Button(btns, text="Eliminar", command=self.delete_user).pack(side=tk.LEFT, padx=6)
        self.refresh()

    def refresh(self):
        for r in self.tree.get_children(): self.tree.delete(r)
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("SELECT id,username,role FROM users")
            for row in cur.fetchall():
                self.tree.insert("", tk.END, values=row)

    def new_user(self):
        dlg = NewUserDialog(self); self.wait_window(dlg)
        if getattr(dlg, "created", False): self.refresh()

    def delete_user(self):
        sel = self.tree.selection()
        if not sel: return
        uid = self.tree.item(sel[0])['values'][0]
        if messagebox.askyesno("Confirmar", "Eliminar usuario?"):
            with sqlite3.connect(DB_PATH) as conn:
                conn.execute("DELETE FROM users WHERE id=?", (uid,))
                conn.commit()
            self.refresh()

class NewUserDialog(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title("Crear usuario")
        self.geometry("320x220")
        ttk.Label(self, text="Usuario:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.e_user = ttk.Entry(self); self.e_user.pack(fill=tk.X, padx=8)
        ttk.Label(self, text="Contraseña:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.e_pw = ttk.Entry(self, show="*"); self.e_pw.pack(fill=tk.X, padx=8)
        ttk.Label(self, text="Rol:").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.combo = ttk.Combobox(self, values=["admin","cajero"]); self.combo.current(1); self.combo.pack(fill=tk.X, padx=8)
        ttk.Button(self, text="Crear", command=self.create).pack(pady=12)

    def create(self):
        u = self.e_user.get().strip(); p = self.e_pw.get().strip(); r = self.combo.get()
        if not u or not p:
            messagebox.showwarning("Faltan", "Ingrese usuario y contraseña")
            return
        ok = create_user(u,p,r)
        if ok:
            messagebox.showinfo("Creado","Usuario creado")
            self.created = True
            self.destroy()
        else:
            messagebox.showerror("Error","Usuario ya existe")

class SettingsWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title("Configuración")
        self.geometry("360x200")
        ttk.Label(self, text="Tasa de impuesto (ej: 0.16 para 16%):").pack(anchor=tk.W, padx=8, pady=(8,0))
        self.e_tax = ttk.Entry(self); self.e_tax.pack(fill=tk.X, padx=8)
        self.e_tax.insert(0, get_setting("tax_rate", "0.00") or "0.00")
        ttk.Button(self, text="Guardar", command=self.save).pack(pady=12)

    def save(self):
        try:
            v = float(self.e_tax.get())
        except:
            messagebox.showerror("Error","Valor inválido")
            return
        set_setting("tax_rate", f"{v:.4f}")
        messagebox.showinfo("Guardado","Configuración actualizada")
        self.destroy()

if __name__ == "__main__":
    init_db()
    login = LoginWindow()
    login.mainloop()
PY

# Make sure files have correct permissions
chmod 644 README.md .gitignore LICENSE main.py build_exe.bat
chmod 755 create_and_push.sh || true

# Stage files
git add README.md .gitignore LICENSE main.py build_exe.bat .github/workflows/build.yml

# Commit
git commit -m "Initial commit - Tiendita POS (main.py, build, workflow, README)" || echo "No changes to commit"

# Push
echo "Pushing to origin $CURRENT_BRANCH ..."
git push origin "$CURRENT_BRANCH"

echo "Hecho. Archivos creados y enviados a remoto (si tenías permisos)."