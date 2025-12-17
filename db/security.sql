USE soporte;
GO

-- =============================================
-- CONFIGURACIÓN DE SEGURIDAD Y ROLES
-- =============================================

-- Crear roles personalizados
CREATE ROLE rol_api;
CREATE ROLE rol_batch;
CREATE ROLE rol_admin;
CREATE ROLE rol_readonly;
GO

-- =============================================
-- PERMISOS PARA ROL API
-- =============================================

-- Permisos de lectura
GRANT SELECT ON Usuarios TO rol_api;
GRANT SELECT ON Tickets TO rol_api;
GRANT SELECT ON Interacciones TO rol_api;
GRANT SELECT ON Adjuntos TO rol_api;
GRANT SELECT ON HistorialCambios TO rol_api;
GRANT SELECT ON Sesiones TO rol_api;

-- Permisos de escritura (INSERT/UPDATE)
GRANT INSERT, UPDATE ON Usuarios TO rol_api;
GRANT INSERT, UPDATE ON Tickets TO rol_api;
GRANT INSERT ON Interacciones TO rol_api;
GRANT INSERT ON Adjuntos TO rol_api;
GRANT INSERT, DELETE ON Sesiones TO rol_api;

-- Permisos sobre vistas
GRANT SELECT ON vw_TicketsCompletos TO rol_api;
GRANT SELECT ON vw_EstadisticasUsuario TO rol_api;

-- Permisos para ejecutar procedimientos
GRANT EXECUTE ON sp_LimpiarSesionesExpiradas TO rol_api;
GRANT EXECUTE ON sp_ObtenerTickets TO rol_api;

-- DENEGAR operaciones peligrosas
DENY DELETE ON Usuarios TO rol_api;
DENY DELETE ON Tickets TO rol_api;
DENY DELETE ON Interacciones TO rol_api;
DENY DELETE ON HistorialCambios TO rol_api;
DENY TRUNCATE TABLE TO rol_api;
GO

-- =============================================
-- PERMISOS PARA ROL BATCH
-- =============================================

GRANT SELECT ON Usuarios TO rol_batch;
GRANT SELECT ON Tickets TO rol_batch;
GRANT SELECT, INSERT ON Interacciones TO rol_batch;
GRANT SELECT ON HistorialCambios TO rol_batch;
GRANT INSERT ON RegistroBackups TO rol_batch;
GRANT EXECUTE ON sp_LimpiarSesionesExpiradas TO rol_batch;

-- DENEGAR operaciones no necesarias
DENY UPDATE ON Usuarios TO rol_batch;
DENY DELETE ON Tickets TO rol_batch;
GO

-- =============================================
-- PERMISOS PARA ROL ADMIN (DBA)
-- =============================================

GRANT CONTROL ON DATABASE::soporte TO rol_admin;
GRANT VIEW ANY DEFINITION TO rol_admin;
GRANT VIEW SERVER STATE TO rol_admin;
GO

-- =============================================
-- PERMISOS PARA ROL READONLY
-- =============================================

GRANT SELECT ON Usuarios TO rol_readonly;
GRANT SELECT ON Tickets TO rol_readonly;
GRANT SELECT ON Interacciones TO rol_readonly;
GRANT SELECT ON HistorialCambios TO rol_readonly;
GRANT SELECT ON vw_TicketsCompletos TO rol_readonly;
GRANT SELECT ON vw_EstadisticasUsuario TO rol_readonly;

-- DENEGAR escritura
DENY INSERT, UPDATE, DELETE ON DATABASE::soporte TO rol_readonly;
GO

-- =============================================
-- CREAR LOGINS Y USUARIOS
-- =============================================

-- Usuario para API (ya existe, actualizamos)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'api_user')
BEGIN
    CREATE LOGIN api_user WITH PASSWORD = 'ApiUser#2025', CHECK_POLICY = ON;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'api_user')
BEGIN
    CREATE USER api_user FOR LOGIN api_user;
END
GO

-- Usuario para Batch Worker
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'batch_user')
BEGIN
    CREATE LOGIN batch_user WITH PASSWORD = 'Batch123!', CHECK_POLICY = ON;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'batch_user')
BEGIN
    CREATE USER batch_user FOR LOGIN batch_user;
END
GO

-- Usuario Administrador DBA
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'admin_dba')
BEGIN
    CREATE LOGIN admin_dba WITH PASSWORD = 'AdminDBA#2025', CHECK_POLICY = ON;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'admin_dba')
BEGIN
    CREATE USER admin_dba FOR LOGIN admin_dba;
END
GO

-- Usuario de solo lectura para reportes
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'readonly_user')
BEGIN
    CREATE LOGIN readonly_user WITH PASSWORD = 'ReadOnly#2025', CHECK_POLICY = ON;
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER readonly_user FOR LOGIN readonly_user;
END
GO

-- =============================================
-- ASIGNAR ROLES A USUARIOS
-- =============================================

ALTER ROLE rol_api ADD MEMBER api_user;
ALTER ROLE rol_batch ADD MEMBER batch_user;
ALTER ROLE rol_admin ADD MEMBER admin_dba;
ALTER ROLE rol_readonly ADD MEMBER readonly_user;
GO

-- =============================================
-- CONFIGURACIÓN DE SEGURIDAD A NIVEL SERVIDOR
-- =============================================

-- Habilitar cifrado de conexiones (requiere certificado en producción)
-- ALTER DATABASE soporte SET ENCRYPTION ON;

-- Habilitar auditoría de cambios
ALTER DATABASE soporte SET CHANGE_TRACKING = ON
(CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
GO

-- =============================================
-- PROCEDIMIENTOS PARA BACKUPS
-- =============================================

-- Procedimiento para Backup Completo
GO
CREATE PROCEDURE sp_BackupCompleto
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ruta NVARCHAR(500);
    DECLARE @nombre NVARCHAR(200);
    DECLARE @fecha NVARCHAR(50) = CONVERT(NVARCHAR, GETDATE(), 112) + '_' + REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', '');
    
    SET @nombre = 'soporte_FULL_' + @fecha + '.bak';
    SET @ruta = 'C:\Backups\' + @nombre;
    
    BEGIN TRY
        -- Realizar backup
        BACKUP DATABASE soporte 
        TO DISK = @ruta
        WITH FORMAT, COMPRESSION, STATS = 10;
        
        -- Registrar en la tabla
        DECLARE @tamano DECIMAL(10,2);
        SET @tamano = (SELECT 
            CAST(SUM(backup_size) / 1024.0 / 1024.0 AS DECIMAL(10,2))
            FROM msdb.dbo.backupset
            WHERE database_name = 'soporte'
            AND backup_set_id = (SELECT MAX(backup_set_id) FROM msdb.dbo.backupset WHERE database_name = 'soporte')
        );
        
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, tamano_mb, estado, mensaje)
        VALUES ('completo', @ruta, @tamano, 'exitoso', 'Backup completo realizado correctamente');
        
        PRINT 'Backup completo exitoso: ' + @ruta;
    END TRY
    BEGIN CATCH
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, estado, mensaje)
        VALUES ('completo', @ruta, 'fallido', ERROR_MESSAGE());
        
        PRINT 'Error en backup: ' + ERROR_MESSAGE();
    END CATCH
END;
GO

-- Procedimiento para Backup Diferencial
GO
CREATE PROCEDURE sp_BackupDiferencial
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ruta NVARCHAR(500);
    DECLARE @nombre NVARCHAR(200);
    DECLARE @fecha NVARCHAR(50) = CONVERT(NVARCHAR, GETDATE(), 112) + '_' + REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', '');
    
    SET @nombre = 'soporte_DIFF_' + @fecha + '.bak';
    SET @ruta = 'C:\Backups\' + @nombre;
    
    BEGIN TRY
        BACKUP DATABASE soporte 
        TO DISK = @ruta
        WITH DIFFERENTIAL, COMPRESSION, STATS = 10;
        
        DECLARE @tamano DECIMAL(10,2);
        SET @tamano = (SELECT 
            CAST(SUM(backup_size) / 1024.0 / 1024.0 AS DECIMAL(10,2))
            FROM msdb.dbo.backupset
            WHERE database_name = 'soporte'
            AND backup_set_id = (SELECT MAX(backup_set_id) FROM msdb.dbo.backupset WHERE database_name = 'soporte')
        );
        
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, tamano_mb, estado, mensaje)
        VALUES ('diferencial', @ruta, @tamano, 'exitoso', 'Backup diferencial realizado correctamente');
        
        PRINT 'Backup diferencial exitoso: ' + @ruta;
    END TRY
    BEGIN CATCH
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, estado, mensaje)
        VALUES ('diferencial', @ruta, 'fallido', ERROR_MESSAGE());
        
        PRINT 'Error en backup: ' + ERROR_MESSAGE();
    END CATCH
END;
GO

-- Procedimiento para Backup de Transacciones (Log)
GO
CREATE PROCEDURE sp_BackupTransaccional
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Verificar que el modelo de recuperación sea FULL
    IF (SELECT recovery_model_desc FROM sys.databases WHERE name = 'soporte') != 'FULL'
    BEGIN
        PRINT 'ADVERTENCIA: El modelo de recuperación debe ser FULL para backups transaccionales';
        RETURN;
    END
    
    DECLARE @ruta NVARCHAR(500);
    DECLARE @nombre NVARCHAR(200);
    DECLARE @fecha NVARCHAR(50) = CONVERT(NVARCHAR, GETDATE(), 112) + '_' + REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', '');
    
    SET @nombre = 'soporte_LOG_' + @fecha + '.trn';
    SET @ruta = 'C:\Backups\' + @nombre;
    
    BEGIN TRY
        BACKUP LOG soporte 
        TO DISK = @ruta
        WITH COMPRESSION, STATS = 10;
        
        DECLARE @tamano DECIMAL(10,2);
        SET @tamano = (SELECT 
            CAST(SUM(backup_size) / 1024.0 / 1024.0 AS DECIMAL(10,2))
            FROM msdb.dbo.backupset
            WHERE database_name = 'soporte'
            AND backup_set_id = (SELECT MAX(backup_set_id) FROM msdb.dbo.backupset WHERE database_name = 'soporte')
        );
        
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, tamano_mb, estado, mensaje)
        VALUES ('transaccional', @ruta, @tamano, 'exitoso', 'Backup de log realizado correctamente');
        
        PRINT 'Backup transaccional exitoso: ' + @ruta;
    END TRY
    BEGIN CATCH
        INSERT INTO RegistroBackups (tipo_backup, ruta_archivo, estado, mensaje)
        VALUES ('transaccional', @ruta, 'fallido', ERROR_MESSAGE());
        
        PRINT 'Error en backup: ' + ERROR_MESSAGE();
    END CATCH
END;
GO

-- =============================================
-- CONFIGURAR MODELO DE RECUPERACIÓN
-- =============================================

ALTER DATABASE soporte SET RECOVERY FULL;
GO

-- =============================================
-- JOB DE MANTENIMIENTO (Ejecutar manualmente o con SQL Agent)
-- =============================================

GO
CREATE PROCEDURE sp_MantenimientoDiario
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT 'Iniciando mantenimiento diario...';
    
    -- 1. Limpiar sesiones expiradas
    EXEC sp_LimpiarSesionesExpiradas;
    
    -- 2. Actualizar estadísticas
    EXEC sp_updatestats;
    
    -- 3. Reorganizar índices fragmentados
    DECLARE @tabla NVARCHAR(128);
    DECLARE @indice NVARCHAR(128);
    
    DECLARE cursor_indices CURSOR FOR
    SELECT 
        OBJECT_NAME(ips.object_id) AS tabla,
        i.name AS indice
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.avg_fragmentation_in_percent > 10
        AND ips.page_count > 100
        AND i.name IS NOT NULL;
    
    OPEN cursor_indices;
    FETCH NEXT FROM cursor_indices INTO @tabla, @indice;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'Reorganizando índice: ' + @indice + ' en tabla: ' + @tabla;
        EXEC('ALTER INDEX [' + @indice + '] ON [' + @tabla + '] REORGANIZE');
        FETCH NEXT FROM cursor_indices INTO @tabla, @indice;
    END
    
    CLOSE cursor_indices;
    DEALLOCATE cursor_indices;
    
    PRINT 'Mantenimiento completado.';
END;
GO

-- =============================================
-- INFORMACIÓN DE CONFIGURACIÓN
-- =============================================

PRINT '==============================================';
PRINT 'CONFIGURACIÓN DE SEGURIDAD COMPLETADA';
PRINT '==============================================';
PRINT '';
PRINT 'USUARIOS CREADOS:';
PRINT '  - api_user (rol_api): Acceso para la API';
PRINT '  - batch_user (rol_batch): Acceso para worker';
PRINT '  - admin_dba (rol_admin): Acceso administrativo';
PRINT '  - readonly_user (rol_readonly): Acceso de lectura';
PRINT '';
PRINT 'PROCEDIMIENTOS DE BACKUP:';
PRINT '  - EXEC sp_BackupCompleto';
PRINT '  - EXEC sp_BackupDiferencial';
PRINT '  - EXEC sp_BackupTransaccional';
PRINT '';
PRINT 'MANTENIMIENTO:';
PRINT '  - EXEC sp_MantenimientoDiario';
PRINT '==============================================';