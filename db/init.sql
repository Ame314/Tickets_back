-- Crear base de datos
CREATE DATABASE soporte;
GO
USE soporte;
GO

-- =============================================
-- TABLAS PRINCIPALES
-- =============================================

-- Tabla de Usuarios con roles
CREATE TABLE Usuarios (
    usuario_id INT IDENTITY PRIMARY KEY,
    nombre NVARCHAR(100) NOT NULL,
    email NVARCHAR(150) UNIQUE NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    rol NVARCHAR(20) NOT NULL DEFAULT 'usuario' CHECK (rol IN ('admin', 'usuario')),
    activo BIT DEFAULT 1,
    ultimo_acceso DATETIME2 NULL,
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    actualizado_en DATETIME2 DEFAULT SYSDATETIME()
);

-- Tabla de Tickets
CREATE TABLE Tickets (
    ticket_id INT IDENTITY PRIMARY KEY,
    usuario_id INT NOT NULL,
    titulo NVARCHAR(200) NOT NULL,
    descripcion NVARCHAR(MAX),
    prioridad NVARCHAR(20) NOT NULL DEFAULT 'media' CHECK (prioridad IN ('baja', 'media', 'alta', 'urgente')),
    estado NVARCHAR(50) NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'en_proceso', 'resuelto', 'cerrado', 'cancelado')),
    categoria NVARCHAR(50),
    asignado_a INT NULL,
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    actualizado_en DATETIME2 DEFAULT SYSDATETIME(),
    cerrado_en DATETIME2 NULL,
    CONSTRAINT FK_Ticket_Usuario FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id),
    CONSTRAINT FK_Ticket_Asignado FOREIGN KEY (asignado_a) REFERENCES Usuarios(usuario_id)
);

-- Tabla de Interacciones/Comentarios
CREATE TABLE Interacciones (
    interaccion_id BIGINT IDENTITY PRIMARY KEY,
    ticket_id INT NOT NULL,
    usuario_id INT NOT NULL,
    mensaje NVARCHAR(MAX) NOT NULL,
    es_interno BIT DEFAULT 0, -- Para notas internas de admin
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Interaccion_Ticket FOREIGN KEY (ticket_id) REFERENCES Tickets(ticket_id),
    CONSTRAINT FK_Interaccion_Usuario FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id)
);

-- Tabla de Archivos Adjuntos
CREATE TABLE Adjuntos (
    adjunto_id INT IDENTITY PRIMARY KEY,
    ticket_id INT NOT NULL,
    nombre_archivo NVARCHAR(255) NOT NULL,
    ruta_archivo NVARCHAR(500) NOT NULL,
    tipo_mime NVARCHAR(100),
    tamano_bytes BIGINT,
    subido_por INT NOT NULL,
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Adjunto_Ticket FOREIGN KEY (ticket_id) REFERENCES Tickets(ticket_id),
    CONSTRAINT FK_Adjunto_Usuario FOREIGN KEY (subido_por) REFERENCES Usuarios(usuario_id)
);

-- Tabla de Historial de Cambios (Auditoría)
CREATE TABLE HistorialCambios (
    historial_id BIGINT IDENTITY PRIMARY KEY,
    ticket_id INT NOT NULL,
    usuario_id INT NOT NULL,
    campo_modificado NVARCHAR(50) NOT NULL,
    valor_anterior NVARCHAR(MAX),
    valor_nuevo NVARCHAR(MAX),
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Historial_Ticket FOREIGN KEY (ticket_id) REFERENCES Tickets(ticket_id),
    CONSTRAINT FK_Historial_Usuario FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id)
);

-- Tabla de Sesiones (para manejo de tokens)
CREATE TABLE Sesiones (
    sesion_id INT IDENTITY PRIMARY KEY,
    usuario_id INT NOT NULL,
    token_hash NVARCHAR(255) NOT NULL,
    ip_address NVARCHAR(50),
    user_agent NVARCHAR(500),
    expira_en DATETIME2 NOT NULL,
    creado_en DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Sesion_Usuario FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id)
);

-- Tabla de Backups
CREATE TABLE RegistroBackups (
    backup_id INT IDENTITY PRIMARY KEY,
    tipo_backup NVARCHAR(20) NOT NULL CHECK (tipo_backup IN ('completo', 'diferencial', 'transaccional')),
    ruta_archivo NVARCHAR(500) NOT NULL,
    tamano_mb DECIMAL(10,2),
    estado NVARCHAR(20) NOT NULL DEFAULT 'exitoso' CHECK (estado IN ('exitoso', 'fallido', 'en_proceso')),
    mensaje NVARCHAR(MAX),
    creado_en DATETIME2 DEFAULT SYSDATETIME()
);

-- =============================================
-- ÍNDICES PARA OPTIMIZACIÓN
-- =============================================

-- Índices en Tickets
CREATE NONCLUSTERED INDEX idx_tickets_usuario ON Tickets(usuario_id, estado);
CREATE NONCLUSTERED INDEX idx_tickets_estado_fecha ON Tickets(estado, creado_en DESC);
CREATE NONCLUSTERED INDEX idx_tickets_asignado ON Tickets(asignado_a, estado);
CREATE NONCLUSTERED INDEX idx_tickets_prioridad ON Tickets(prioridad, estado);

-- Índices en Interacciones
CREATE NONCLUSTERED INDEX idx_interacciones_ticket_fecha ON Interacciones(ticket_id, creado_en DESC);
CREATE NONCLUSTERED INDEX idx_interacciones_usuario ON Interacciones(usuario_id);

-- Índices en Usuarios
CREATE NONCLUSTERED INDEX idx_usuarios_email ON Usuarios(email) WHERE activo = 1;
CREATE NONCLUSTERED INDEX idx_usuarios_rol ON Usuarios(rol) WHERE activo = 1;

-- Índices en Sesiones
CREATE NONCLUSTERED INDEX idx_sesiones_usuario ON Sesiones(usuario_id);
CREATE NONCLUSTERED INDEX idx_sesiones_expiracion ON Sesiones(expira_en);

-- Índices en Historial
CREATE NONCLUSTERED INDEX idx_historial_ticket_fecha ON HistorialCambios(ticket_id, creado_en DESC);

-- =============================================
-- TRIGGERS PARA AUDITORÍA Y ACTUALIZACIÓN
-- =============================================

-- Trigger para actualizar fecha de modificación en Tickets
GO
CREATE TRIGGER trg_Tickets_Actualizado
ON Tickets
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Tickets
    SET actualizado_en = SYSDATETIME()
    WHERE ticket_id IN (SELECT ticket_id FROM inserted);
END;
GO

-- Trigger para registrar cambios en el historial
GO
CREATE TRIGGER trg_Tickets_Historial
ON Tickets
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Registrar cambios de estado
    IF UPDATE(estado)
    BEGIN
        INSERT INTO HistorialCambios (ticket_id, usuario_id, campo_modificado, valor_anterior, valor_nuevo)
        SELECT 
            i.ticket_id,
            ISNULL(i.asignado_a, i.usuario_id),
            'estado',
            d.estado,
            i.estado
        FROM inserted i
        INNER JOIN deleted d ON i.ticket_id = d.ticket_id
        WHERE i.estado != d.estado;
    END
    
    -- Registrar cambios de prioridad
    IF UPDATE(prioridad)
    BEGIN
        INSERT INTO HistorialCambios (ticket_id, usuario_id, campo_modificado, valor_anterior, valor_nuevo)
        SELECT 
            i.ticket_id,
            ISNULL(i.asignado_a, i.usuario_id),
            'prioridad',
            d.prioridad,
            i.prioridad
        FROM inserted i
        INNER JOIN deleted d ON i.ticket_id = d.ticket_id
        WHERE i.prioridad != d.prioridad;
    END
    
    -- Registrar cambios de asignación
    IF UPDATE(asignado_a)
    BEGIN
        INSERT INTO HistorialCambios (ticket_id, usuario_id, campo_modificado, valor_anterior, valor_nuevo)
        SELECT 
            i.ticket_id,
            ISNULL(i.asignado_a, i.usuario_id),
            'asignado_a',
            CAST(d.asignado_a AS NVARCHAR),
            CAST(i.asignado_a AS NVARCHAR)
        FROM inserted i
        INNER JOIN deleted d ON i.ticket_id = d.ticket_id
        WHERE ISNULL(i.asignado_a, 0) != ISNULL(d.asignado_a, 0);
    END
END;
GO

-- =============================================
-- VISTAS ÚTILES
-- =============================================

-- Vista de tickets con información del usuario
GO
CREATE VIEW vw_TicketsCompletos AS
SELECT 
    t.ticket_id,
    t.titulo,
    t.descripcion,
    t.prioridad,
    t.estado,
    t.categoria,
    u.nombre AS nombre_usuario,
    u.email AS email_usuario,
    a.nombre AS asignado_nombre,
    a.email AS asignado_email,
    t.creado_en,
    t.actualizado_en,
    t.cerrado_en,
    (SELECT COUNT(*) FROM Interacciones WHERE ticket_id = t.ticket_id) AS total_interacciones
FROM Tickets t
INNER JOIN Usuarios u ON t.usuario_id = u.usuario_id
LEFT JOIN Usuarios a ON t.asignado_a = a.usuario_id;
GO

-- Vista de estadísticas por usuario
GO
CREATE VIEW vw_EstadisticasUsuario AS
SELECT 
    u.usuario_id,
    u.nombre,
    u.email,
    u.rol,
    COUNT(t.ticket_id) AS total_tickets,
    SUM(CASE WHEN t.estado = 'abierto' THEN 1 ELSE 0 END) AS tickets_abiertos,
    SUM(CASE WHEN t.estado = 'en_proceso' THEN 1 ELSE 0 END) AS tickets_en_proceso,
    SUM(CASE WHEN t.estado = 'resuelto' THEN 1 ELSE 0 END) AS tickets_resueltos,
    SUM(CASE WHEN t.estado = 'cerrado' THEN 1 ELSE 0 END) AS tickets_cerrados
FROM Usuarios u
LEFT JOIN Tickets t ON u.usuario_id = t.usuario_id
GROUP BY u.usuario_id, u.nombre, u.email, u.rol;
GO

-- =============================================
-- PROCEDIMIENTOS ALMACENADOS
-- =============================================

-- Procedimiento para limpiar sesiones expiradas
GO
CREATE PROCEDURE sp_LimpiarSesionesExpiradas
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Sesiones WHERE expira_en < SYSDATETIME();
    SELECT @@ROWCOUNT AS sesiones_eliminadas;
END;
GO

-- Procedimiento para obtener tickets con paginación
GO
CREATE PROCEDURE sp_ObtenerTickets
    @usuario_id INT = NULL,
    @estado NVARCHAR(50) = NULL,
    @pagina INT = 1,
    @por_pagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @offset INT = (@pagina - 1) * @por_pagina;
    
    SELECT 
        t.*,
        u.nombre AS nombre_usuario,
        a.nombre AS asignado_nombre,
        (SELECT COUNT(*) FROM Interacciones WHERE ticket_id = t.ticket_id) AS total_interacciones
    FROM Tickets t
    INNER JOIN Usuarios u ON t.usuario_id = u.usuario_id
    LEFT JOIN Usuarios a ON t.asignado_a = a.usuario_id
    WHERE (@usuario_id IS NULL OR t.usuario_id = @usuario_id)
        AND (@estado IS NULL OR t.estado = @estado)
    ORDER BY t.creado_en DESC
    OFFSET @offset ROWS
    FETCH NEXT @por_pagina ROWS ONLY;
END;
GO

-- =============================================
-- DATOS INICIALES
-- =============================================

-- Crear usuario administrador (password: Admin123!)
INSERT INTO Usuarios (nombre, email, password_hash, rol)
VALUES ('Administrador', 'admin@soporte.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5oBzCiuuBmmoi', 'admin');

-- Crear usuario de prueba (password: User123!)
INSERT INTO Usuarios (nombre, email, password_hash, rol)
VALUES ('Usuario Demo', 'user@demo.com', '$2b$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'usuario');

GO
PRINT 'Base de datos inicializada correctamente';
PRINT 'Usuario admin: admin@soporte.com / Admin123!';
PRINT 'Usuario demo: user@demo.com / User123!';