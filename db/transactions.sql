SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRAN;

BEGIN TRY
    UPDATE Tickets
    SET estado = 'CERRADO'
    WHERE ticket_id = 1;

    INSERT INTO Interacciones(ticket_id, mensaje)
    VALUES (1, 'Ticket cerrado por operador');

    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
END CATCH;
