USE soporte;
GO

CREATE ROLE rol_api;
CREATE ROLE rol_batch;

GRANT SELECT, INSERT, UPDATE ON Usuarios TO rol_api;
GRANT SELECT, INSERT, UPDATE ON Tickets TO rol_api;
GRANT SELECT, INSERT ON Interacciones TO rol_api;
DENY DELETE TO rol_api;

GRANT SELECT ON Usuarios TO rol_batch;
GRANT SELECT ON Tickets TO rol_batch;
GRANT EXECUTE TO rol_batch;

CREATE LOGIN api_user WITH PASSWORD = 'Api123!';
CREATE LOGIN batch_user WITH PASSWORD = 'Batch123!';

CREATE USER api_user FOR LOGIN api_user;
CREATE USER batch_user FOR LOGIN batch_user;

ALTER ROLE rol_api ADD MEMBER api_user;
ALTER ROLE rol_batch ADD MEMBER batch_user;
