# Sistema de Gestión de Tickets

Sistema completo de gestión de tickets con autenticación, panel de administración y panel de usuario. Desarrollado con FastAPI (backend), Next.js (frontend), SQL Server y Redis.

## 🏗️ Arquitectura

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Next.js   │────▶│   FastAPI   │────▶│ SQL Server  │
│  Frontend   │     │     API     │     │  Database   │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │    Redis    │
                    │    Cache    │
                    └─────────────┘
                           ▲
                           │
                    ┌─────────────┐
                    │   Batch     │
                    │   Worker    │
                    └─────────────┘
```

## 🚀 Características

### Backend (FastAPI)
- ✅ Autenticación JWT con bcrypt
- ✅ Sistema de roles (Admin/Usuario)
- ✅ API RESTful completa
- ✅ Validación con Pydantic
- ✅ Caché con Redis
- ✅ Conexión segura a SQL Server

### Frontend (Next.js 16)
- ✅ Interfaz moderna con Tailwind CSS 4
- ✅ Panel de administración completo
- ✅ Dashboard de usuario
- ✅ Sistema de autenticación
- ✅ Gestión de tickets en tiempo real
- ✅ Sistema de comentarios

### Base de Datos (SQL Server)
- ✅ Modelo relacional completo
- ✅ Sistema de roles y permisos
- ✅ Triggers para auditoría
- ✅ Índices optimizados
- ✅ Vistas para reportes
- ✅ Procedimientos almacenados
- ✅ Sistema de backups automatizados

## 📋 Requisitos Previos

- Docker & Docker Compose
- 4GB RAM mínimo
- Puertos disponibles: 1433, 6379, 8000, 3000

## 🔧 Instalación

### 1. Clonar el proyecto

```bash
git clone <tu-repositorio>
cd adb_practica
```

### 2. Crear estructura de directorios

```bash
mkdir -p backups
mkdir -p db
```

### 3. Configurar archivos de base de datos

Coloca los siguientes archivos en la carpeta `db/`:
- `init.sql` - Estructura de base de datos
- `security.sql` - Configuración de seguridad y backups

### 4. Levantar los servicios

```bash
docker-compose up -d
```

### 5. Inicializar la base de datos

Espera 30 segundos para que SQL Server inicie completamente, luego:

```bash
# Conectarse a SQL Server
docker exec -it sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "Password123!" \
  -i /db/init.sql

# Configurar seguridad
docker exec -it sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "Password123!" \
  -i /db/security.sql
```

### 6. Instalar dependencias del frontend

```bash
cd frontend
npm install
cd ..
```

## 🎯 Uso

### Acceder a la aplicación

- Frontend: http://localhost:3000
- API Docs: http://localhost:8000/docs
- SQL Server: localhost:1433
- Redis: localhost:6379

### Usuarios de prueba

**Administrador:**
- Email: `admin@soporte.com`
- Password: `Admin123!`

**Usuario:**
- Email: `user@demo.com`
- Password: `User123!`

## 📊 Estructura del Proyecto

```
adb_practica/
├── api/
│   ├── Dockerfile
│   ├── main.py          # API FastAPI completa
│   └── requirements.txt
├── batch/
│   ├── Dockerfile
│   ├── worker.py        # Worker para tareas batch
│   └── requirements.txt
├── db/
│   ├── init.sql         # Estructura de base de datos
│   ├── security.sql     # Seguridad y backups
│   ├── roles.sql        # (deprecated)
│   └── transactions.sql # Ejemplos de transacciones
├── frontend/
│   ├── app/
│   │   ├── login/
│   │   │   └── page.tsx
│   │   ├── registro/
│   │   │   └── page.tsx
│   │   ├── dashboard/
│   │   │   └── page.tsx
│   │   ├── admin/
│   │   │   └── page.tsx
│   │   ├── tickets/
│   │   │   └── [id]/
│   │   │       └── page.tsx
│   │   ├── globals.css
│   │   └── page.tsx
│   ├── Dockerfile
│   ├── package.json
│   └── next.config.ts
├── backups/             # Carpeta para backups automáticos
├── docker-compose.yml
└── README.md
```

## 🔒 Seguridad

### Sistema de Roles

**ROL API (`rol_api`):**
- SELECT en todas las tablas principales
- INSERT/UPDATE en Usuarios, Tickets, Interacciones
- DENY DELETE para proteger datos históricos

**ROL BATCH (`rol_batch`):**
- SELECT limitado
- INSERT en Interacciones
- Ejecución de procedimientos específicos

**ROL ADMIN (`rol_admin`):**
- Control total sobre la base de datos
- Gestión de usuarios y permisos
- Acceso a funciones administrativas

**ROL READONLY (`rol_readonly`):**
- Solo lectura en todas las tablas
- Acceso a vistas y reportes

### Backups Automatizados

El sistema incluye procedimientos para:

```sql
-- Backup completo
EXEC sp_BackupCompleto;

-- Backup diferencial
EXEC sp_BackupDiferencial;

-- Backup transaccional (log)
EXEC sp_BackupTransaccional;

-- Mantenimiento diario
EXEC sp_MantenimientoDiario;
```

Los backups se guardan en `/var/opt/mssql/backup` (mapeado a `./backups`)

### Configuración de Seguridad

- Contraseñas hasheadas con bcrypt
- Tokens JWT con expiración
- Validación de roles en cada endpoint
- HTTPS recomendado en producción
- Variables de entorno para secretos

## 📈 Monitoreo

### Health Check

```bash
curl http://localhost:8000/health
```

### Estadísticas Admin

```bash
curl -H "Authorization: Bearer <token>" \
  http://localhost:8000/admin/estadisticas
```

### Logs

```bash
# Ver logs de la API
docker logs api -f

# Ver logs de SQL Server
docker logs sqlserver -f

# Ver logs del worker
docker logs batch -f
```

## 🛠️ Mantenimiento

### Backup Manual

```bash
docker exec sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "Password123!" \
  -Q "EXEC sp_BackupCompleto"
```

### Limpiar Sesiones Expiradas

```bash
docker exec sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "Password123!" \
  -Q "USE soporte; EXEC sp_LimpiarSesionesExpiradas"
```

### Reiniciar Servicios

```bash
# Reiniciar todo
docker-compose restart

# Reiniciar servicio específico
docker-compose restart api
```

## 🐛 Solución de Problemas

### SQL Server no inicia

```bash
# Verificar logs
docker logs sqlserver

# Aumentar memoria del contenedor
# En docker-compose.yml agregar:
# deploy:
#   resources:
#     limits:
#       memory: 2G
```

### API no conecta a SQL Server

```bash
# Verificar que SQL Server esté listo
docker exec sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "Password123!" \
  -Q "SELECT 1"

# Reiniciar API
docker-compose restart api
```

### Frontend no conecta a API

1. Verificar que API esté corriendo: `curl http://localhost:8000/health`
2. Verificar CORS en `api/main.py`
3. Verificar variables de entorno en frontend

## 📝 API Endpoints

### Autenticación
- `POST /auth/registro` - Registrar nuevo usuario
- `POST /auth/login` - Iniciar sesión
- `GET /auth/me` - Obtener usuario actual

### Tickets
- `GET /tickets` - Listar tickets (con filtros)
- `POST /tickets` - Crear ticket
- `GET /tickets/{id}` - Obtener ticket específico
- `PUT /tickets/{id}` - Actualizar ticket

### Interacciones
- `GET /tickets/{id}/interacciones` - Listar comentarios
- `POST /tickets/{id}/interacciones` - Agregar comentario

### Administración
- `GET /admin/estadisticas` - Estadísticas generales
- `GET /admin/usuarios` - Listar usuarios

## 🚢 Despliegue en Producción

### Configuraciones Importantes

1. **Cambiar JWT_SECRET:**
```bash
export JWT_SECRET="tu-secreto-super-seguro-aleatorio"
```

2. **Usar contraseñas fuertes:**
- Cambiar `SA_PASSWORD` en docker-compose.yml
- Actualizar contraseñas de usuarios de BD en `security.sql`

3. **Habilitar HTTPS:**
- Usar nginx como reverse proxy
- Obtener certificados SSL con Let's Encrypt

4. **Configurar backups externos:**
- Sincronizar carpeta `/backups` con almacenamiento en la nube
- Configurar cron jobs para backups automáticos

5. **Monitoreo:**
- Implementar Prometheus + Grafana
- Configurar alertas de errores
- Logs centralizados con ELK Stack

## 👥 Contribución

1. Fork del proyecto
2. Crear rama feature (`git checkout -b feature/AmazingFeature`)
3. Commit cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abrir Pull Request

## 📄 Licencia

Este proyecto es parte de una práctica académica de Arquitectura de Datos.

## 🙏 Agradecimientos

- FastAPI por el excelente framework
- Next.js por el desarrollo frontend moderno
- Microsoft SQL Server por la robustez empresarial
- Redis por el caché de alto rendimiento