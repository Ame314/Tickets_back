from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime, timedelta
import pyodbc
import redis
import bcrypt
import jwt
import os
from enum import Enum

# =============================================
# CONFIGURACIÓN
# =============================================

app = FastAPI(
    title="Sistema de Gestión de Tickets",
    description="API completa para gestión de tickets con autenticación y roles",
    version="2.0"
)

# JWT Configuration
SECRET_KEY = os.getenv("JWT_SECRET", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 horas

# Database Connection
conn_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver;"
    "DATABASE=soporte;"
    "UID=api_user;"
    "PWD=ApiUser#2025;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

# Redis Connection
r = redis.Redis(host="redis", port=6379, decode_responses=True)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()

# =============================================
# ENUMS Y MODELOS
# =============================================

class RolEnum(str, Enum):
    admin = "admin"
    usuario = "usuario"

class EstadoTicket(str, Enum):
    abierto = "abierto"
    en_proceso = "en_proceso"
    resuelto = "resuelto"
    cerrado = "cerrado"
    cancelado = "cancelado"

class PrioridadTicket(str, Enum):
    baja = "baja"
    media = "media"
    alta = "alta"
    urgente = "urgente"

# Modelos Pydantic
class UsuarioRegistro(BaseModel):
    nombre: str
    email: EmailStr
    password: str
    rol: Optional[RolEnum] = RolEnum.usuario

class UsuarioLogin(BaseModel):
    email: EmailStr
    password: str

class UsuarioResponse(BaseModel):
    usuario_id: int
    nombre: str
    email: str
    rol: str
    activo: bool
    creado_en: datetime

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    usuario: UsuarioResponse

class TicketCrear(BaseModel):
    titulo: str
    descripcion: Optional[str] = None
    prioridad: PrioridadTicket = PrioridadTicket.media
    categoria: Optional[str] = None

class TicketActualizar(BaseModel):
    titulo: Optional[str] = None
    descripcion: Optional[str] = None
    prioridad: Optional[PrioridadTicket] = None
    estado: Optional[EstadoTicket] = None
    categoria: Optional[str] = None
    asignado_a: Optional[int] = None

class TicketResponse(BaseModel):
    ticket_id: int
    usuario_id: int
    titulo: str
    descripcion: Optional[str]
    prioridad: str
    estado: str
    categoria: Optional[str]
    asignado_a: Optional[int]
    creado_en: datetime
    actualizado_en: datetime
    nombre_usuario: Optional[str] = None
    asignado_nombre: Optional[str] = None
    total_interacciones: int = 0

class InteraccionCrear(BaseModel):
    mensaje: str
    es_interno: bool = False

class InteraccionResponse(BaseModel):
    interaccion_id: int
    ticket_id: int
    usuario_id: int
    mensaje: str
    es_interno: bool
    creado_en: datetime
    nombre_usuario: Optional[str] = None

class EstadisticasResponse(BaseModel):
    total_tickets: int
    tickets_abiertos: int
    tickets_en_proceso: int
    tickets_resueltos: int
    tickets_cerrados: int
    tickets_por_prioridad: dict

# =============================================
# FUNCIONES DE AUTENTICACIÓN
# =============================================

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_db():
    conn = pyodbc.connect(conn_str)
    try:
        yield conn
    finally:
        conn.close()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    conn: pyodbc.Connection = Depends(get_db)
) -> dict:
    token = credentials.credentials
    
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        usuario_id: int = payload.get("sub")
        if usuario_id is None:
            raise HTTPException(status_code=401, detail="Token inválido")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expirado")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Token inválido")
    
    cursor = conn.cursor()
    cursor.execute(
        "SELECT usuario_id, nombre, email, rol, activo FROM Usuarios WHERE usuario_id = ?",
        usuario_id
    )
    row = cursor.fetchone()
    
    if not row or not row.activo:
        raise HTTPException(status_code=401, detail="Usuario no encontrado o inactivo")
    
    return {
        "usuario_id": row.usuario_id,
        "nombre": row.nombre,
        "email": row.email,
        "rol": row.rol,
        "activo": row.activo
    }

async def require_admin(current_user: dict = Depends(get_current_user)):
    if current_user["rol"] != "admin":
        raise HTTPException(status_code=403, detail="Acceso denegado: se requiere rol de administrador")
    return current_user

# =============================================
# ENDPOINTS DE AUTENTICACIÓN
# =============================================

@app.post("/auth/registro", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def registrar_usuario(usuario: UsuarioRegistro, conn: pyodbc.Connection = Depends(get_db)):
    cursor = conn.cursor()
    
    # Verificar si el email ya existe
    cursor.execute("SELECT email FROM Usuarios WHERE email = ?", usuario.email)
    if cursor.fetchone():
        raise HTTPException(status_code=400, detail="El email ya está registrado")
    
    # Hash de la contraseña
    password_hash = hash_password(usuario.password)
    
    # Insertar usuario
    cursor.execute(
        """INSERT INTO Usuarios (nombre, email, password_hash, rol) 
           OUTPUT INSERTED.usuario_id, INSERTED.nombre, INSERTED.email, INSERTED.rol, 
                  INSERTED.activo, INSERTED.creado_en
           VALUES (?, ?, ?, ?)""",
        usuario.nombre, usuario.email, password_hash, usuario.rol.value
    )
    row = cursor.fetchone()
    conn.commit()
    
    # Crear token
    access_token = create_access_token({"sub": row.usuario_id, "rol": row.rol})
    
    usuario_response = UsuarioResponse(
        usuario_id=row.usuario_id,
        nombre=row.nombre,
        email=row.email,
        rol=row.rol,
        activo=row.activo,
        creado_en=row.creado_en
    )
    
    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        usuario=usuario_response
    )

@app.post("/auth/login", response_model=TokenResponse)
def login(usuario: UsuarioLogin, conn: pyodbc.Connection = Depends(get_db)):
    cursor = conn.cursor()
    
    cursor.execute(
        """SELECT usuario_id, nombre, email, password_hash, rol, activo, creado_en 
           FROM Usuarios WHERE email = ?""",
        usuario.email
    )
    row = cursor.fetchone()
    
    if not row or not verify_password(usuario.password, row.password_hash):
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    
    if not row.activo:
        raise HTTPException(status_code=403, detail="Usuario inactivo")
    
    # Actualizar último acceso
    cursor.execute(
        "UPDATE Usuarios SET ultimo_acceso = SYSDATETIME() WHERE usuario_id = ?",
        row.usuario_id
    )
    conn.commit()
    
    # Crear token
    access_token = create_access_token({"sub": row.usuario_id, "rol": row.rol})
    
    usuario_response = UsuarioResponse(
        usuario_id=row.usuario_id,
        nombre=row.nombre,
        email=row.email,
        rol=row.rol,
        activo=row.activo,
        creado_en=row.creado_en
    )
    
    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        usuario=usuario_response
    )

@app.get("/auth/me", response_model=UsuarioResponse)
def obtener_usuario_actual(current_user: dict = Depends(get_current_user)):
    return UsuarioResponse(**current_user)

# =============================================
# ENDPOINTS DE TICKETS
# =============================================

@app.post("/tickets", response_model=TicketResponse, status_code=status.HTTP_201_CREATED)
def crear_ticket(
    ticket: TicketCrear,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    cursor.execute(
        """INSERT INTO Tickets (usuario_id, titulo, descripcion, prioridad, categoria)
           OUTPUT INSERTED.ticket_id, INSERTED.usuario_id, INSERTED.titulo, 
                  INSERTED.descripcion, INSERTED.prioridad, INSERTED.estado, 
                  INSERTED.categoria, INSERTED.asignado_a, INSERTED.creado_en, 
                  INSERTED.actualizado_en
           VALUES (?, ?, ?, ?, ?)""",
        current_user["usuario_id"], ticket.titulo, ticket.descripcion, 
        ticket.prioridad.value, ticket.categoria
    )
    row = cursor.fetchone()
    conn.commit()
    
    # Invalidar caché
    r.delete(f"ticket:{row.ticket_id}")
    
    return TicketResponse(
        ticket_id=row.ticket_id,
        usuario_id=row.usuario_id,
        titulo=row.titulo,
        descripcion=row.descripcion,
        prioridad=row.prioridad,
        estado=row.estado,
        categoria=row.categoria,
        asignado_a=row.asignado_a,
        creado_en=row.creado_en,
        actualizado_en=row.actualizado_en,
        nombre_usuario=current_user["nombre"]
    )

@app.get("/tickets", response_model=List[TicketResponse])
def listar_tickets(
    estado: Optional[EstadoTicket] = None,
    prioridad: Optional[PrioridadTicket] = None,
    page: int = 1,
    limit: int = 20,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    # Los usuarios normales solo ven sus tickets, los admin ven todos
    query = """
        SELECT t.*, u.nombre as nombre_usuario, a.nombre as asignado_nombre,
               (SELECT COUNT(*) FROM Interacciones WHERE ticket_id = t.ticket_id) as total_interacciones
        FROM Tickets t
        INNER JOIN Usuarios u ON t.usuario_id = u.usuario_id
        LEFT JOIN Usuarios a ON t.asignado_a = a.usuario_id
        WHERE 1=1
    """
    params = []
    
    if current_user["rol"] != "admin":
        query += " AND (t.usuario_id = ? OR t.asignado_a = ?)"
        params.extend([current_user["usuario_id"], current_user["usuario_id"]])
    
    if estado:
        query += " AND t.estado = ?"
        params.append(estado.value)
    
    if prioridad:
        query += " AND t.prioridad = ?"
        params.append(prioridad.value)
    
    query += " ORDER BY t.creado_en DESC OFFSET ? ROWS FETCH NEXT ? ROWS ONLY"
    params.extend([(page - 1) * limit, limit])
    
    cursor.execute(query, params)
    rows = cursor.fetchall()
    
    return [TicketResponse(
        ticket_id=row.ticket_id,
        usuario_id=row.usuario_id,
        titulo=row.titulo,
        descripcion=row.descripcion,
        prioridad=row.prioridad,
        estado=row.estado,
        categoria=row.categoria,
        asignado_a=row.asignado_a,
        creado_en=row.creado_en,
        actualizado_en=row.actualizado_en,
        nombre_usuario=row.nombre_usuario,
        asignado_nombre=row.asignado_nombre,
        total_interacciones=row.total_interacciones
    ) for row in rows]

@app.get("/tickets/{ticket_id}", response_model=TicketResponse)
def obtener_ticket(
    ticket_id: int,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    # Intentar obtener de caché
    cache_key = f"ticket:{ticket_id}"
    cached = r.get(cache_key)
    
    cursor = conn.cursor()
    cursor.execute(
        """SELECT t.*, u.nombre as nombre_usuario, a.nombre as asignado_nombre,
                  (SELECT COUNT(*) FROM Interacciones WHERE ticket_id = t.ticket_id) as total_interacciones
           FROM Tickets t
           INNER JOIN Usuarios u ON t.usuario_id = u.usuario_id
           LEFT JOIN Usuarios a ON t.asignado_a = a.usuario_id
           WHERE t.ticket_id = ?""",
        ticket_id
    )
    row = cursor.fetchone()
    
    if not row:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    
    # Verificar permisos
    if current_user["rol"] != "admin" and row.usuario_id != current_user["usuario_id"] and row.asignado_a != current_user["usuario_id"]:
        raise HTTPException(status_code=403, detail="No tiene permisos para ver este ticket")
    
    # Guardar en caché
    r.setex(cache_key, 300, row.estado)  # 5 minutos
    
    return TicketResponse(
        ticket_id=row.ticket_id,
        usuario_id=row.usuario_id,
        titulo=row.titulo,
        descripcion=row.descripcion,
        prioridad=row.prioridad,
        estado=row.estado,
        categoria=row.categoria,
        asignado_a=row.asignado_a,
        creado_en=row.creado_en,
        actualizado_en=row.actualizado_en,
        nombre_usuario=row.nombre_usuario,
        asignado_nombre=row.asignado_nombre,
        total_interacciones=row.total_interacciones
    )

@app.put("/tickets/{ticket_id}", response_model=TicketResponse)
def actualizar_ticket(
    ticket_id: int,
    ticket_update: TicketActualizar,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    # Verificar que el ticket existe y obtener permisos
    cursor.execute("SELECT usuario_id, asignado_a FROM Tickets WHERE ticket_id = ?", ticket_id)
    ticket_row = cursor.fetchone()
    
    if not ticket_row:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    
    # Solo el dueño, asignado o admin pueden actualizar
    if (current_user["rol"] != "admin" and 
        ticket_row.usuario_id != current_user["usuario_id"] and 
        ticket_row.asignado_a != current_user["usuario_id"]):
        raise HTTPException(status_code=403, detail="No tiene permisos para actualizar este ticket")
    
    # Construir query de actualización
    updates = []
    params = []
    
    if ticket_update.titulo is not None:
        updates.append("titulo = ?")
        params.append(ticket_update.titulo)
    
    if ticket_update.descripcion is not None:
        updates.append("descripcion = ?")
        params.append(ticket_update.descripcion)
    
    if ticket_update.prioridad is not None:
        updates.append("prioridad = ?")
        params.append(ticket_update.prioridad.value)
    
    if ticket_update.estado is not None:
        updates.append("estado = ?")
        params.append(ticket_update.estado.value)
        if ticket_update.estado in [EstadoTicket.cerrado, EstadoTicket.resuelto]:
            updates.append("cerrado_en = SYSDATETIME()")
    
    if ticket_update.categoria is not None:
        updates.append("categoria = ?")
        params.append(ticket_update.categoria)
    
    if ticket_update.asignado_a is not None:
        if current_user["rol"] != "admin":
            raise HTTPException(status_code=403, detail="Solo administradores pueden asignar tickets")
        updates.append("asignado_a = ?")
        params.append(ticket_update.asignado_a)
    
    if not updates:
        raise HTTPException(status_code=400, detail="No hay campos para actualizar")
    
    params.append(ticket_id)
    
    query = f"UPDATE Tickets SET {', '.join(updates)} WHERE ticket_id = ?"
    cursor.execute(query, params)
    conn.commit()
    
    # Invalidar caché
    r.delete(f"ticket:{ticket_id}")
    
    # Retornar ticket actualizado
    return obtener_ticket(ticket_id, current_user, conn)

# =============================================
# ENDPOINTS DE INTERACCIONES
# =============================================

@app.post("/tickets/{ticket_id}/interacciones", response_model=InteraccionResponse)
def crear_interaccion(
    ticket_id: int,
    interaccion: InteraccionCrear,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    # Verificar que el ticket existe y permisos
    cursor.execute("SELECT usuario_id, asignado_a FROM Tickets WHERE ticket_id = ?", ticket_id)
    ticket_row = cursor.fetchone()
    
    if not ticket_row:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    
    # Verificar permisos para comentarios internos
    if interaccion.es_interno and current_user["rol"] != "admin":
        raise HTTPException(status_code=403, detail="Solo administradores pueden crear notas internas")
    
    cursor.execute(
        """INSERT INTO Interacciones (ticket_id, usuario_id, mensaje, es_interno)
           OUTPUT INSERTED.interaccion_id, INSERTED.ticket_id, INSERTED.usuario_id, 
                  INSERTED.mensaje, INSERTED.es_interno, INSERTED.creado_en
           VALUES (?, ?, ?, ?)""",
        ticket_id, current_user["usuario_id"], interaccion.mensaje, interaccion.es_interno
    )
    row = cursor.fetchone()
    conn.commit()
    
    return InteraccionResponse(
        interaccion_id=row.interaccion_id,
        ticket_id=row.ticket_id,
        usuario_id=row.usuario_id,
        mensaje=row.mensaje,
        es_interno=row.es_interno,
        creado_en=row.creado_en,
        nombre_usuario=current_user["nombre"]
    )

@app.get("/tickets/{ticket_id}/interacciones", response_model=List[InteraccionResponse])
def listar_interacciones(
    ticket_id: int,
    current_user: dict = Depends(get_current_user),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    # Verificar acceso al ticket
    cursor.execute("SELECT usuario_id, asignado_a FROM Tickets WHERE ticket_id = ?", ticket_id)
    ticket_row = cursor.fetchone()
    
    if not ticket_row:
        raise HTTPException(status_code=404, detail="Ticket no encontrado")
    
    if (current_user["rol"] != "admin" and 
        ticket_row.usuario_id != current_user["usuario_id"] and 
        ticket_row.asignado_a != current_user["usuario_id"]):
        raise HTTPException(status_code=403, detail="No tiene permisos para ver este ticket")
    
    # Los usuarios normales no ven notas internas
    query = """
        SELECT i.*, u.nombre as nombre_usuario
        FROM Interacciones i
        INNER JOIN Usuarios u ON i.usuario_id = u.usuario_id
        WHERE i.ticket_id = ?
    """
    
    if current_user["rol"] != "admin":
        query += " AND i.es_interno = 0"
    
    query += " ORDER BY i.creado_en ASC"
    
    cursor.execute(query, ticket_id)
    rows = cursor.fetchall()
    
    return [InteraccionResponse(
        interaccion_id=row.interaccion_id,
        ticket_id=row.ticket_id,
        usuario_id=row.usuario_id,
        mensaje=row.mensaje,
        es_interno=row.es_interno,
        creado_en=row.creado_en,
        nombre_usuario=row.nombre_usuario
    ) for row in rows]

# =============================================
# ENDPOINTS DE ADMINISTRACIÓN
# =============================================

@app.get("/admin/estadisticas", response_model=EstadisticasResponse)
def obtener_estadisticas(
    admin_user: dict = Depends(require_admin),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estado = 'abierto' THEN 1 ELSE 0 END) as abiertos,
            SUM(CASE WHEN estado = 'en_proceso' THEN 1 ELSE 0 END) as en_proceso,
            SUM(CASE WHEN estado = 'resuelto' THEN 1 ELSE 0 END) as resueltos,
            SUM(CASE WHEN estado = 'cerrado' THEN 1 ELSE 0 END) as cerrados
        FROM Tickets
    """)
    row = cursor.fetchone()
    
    cursor.execute("""
        SELECT prioridad, COUNT(*) as cantidad
        FROM Tickets
        GROUP BY prioridad
    """)
    prioridades = {row.prioridad: row.cantidad for row in cursor.fetchall()}
    
    return EstadisticasResponse(
        total_tickets=row.total,
        tickets_abiertos=row.abiertos,
        tickets_en_proceso=row.en_proceso,
        tickets_resueltos=row.resueltos,
        tickets_cerrados=row.cerrados,
        tickets_por_prioridad=prioridades
    )

@app.get("/admin/usuarios", response_model=List[UsuarioResponse])
def listar_usuarios(
    admin_user: dict = Depends(require_admin),
    conn: pyodbc.Connection = Depends(get_db)
):
    cursor = conn.cursor()
    cursor.execute("""
        SELECT usuario_id, nombre, email, rol, activo, creado_en
        FROM Usuarios
        ORDER BY creado_en DESC
    """)
    
    return [UsuarioResponse(
        usuario_id=row.usuario_id,
        nombre=row.nombre,
        email=row.email,
        rol=row.rol,
        activo=row.activo,
        creado_en=row.creado_en
    ) for row in cursor.fetchall()]

# =============================================
# HEALTH CHECK
# =============================================

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "database": "connected",
        "redis": "connected" if r.ping() else "disconnected"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)