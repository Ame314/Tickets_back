import time
import redis
import pyodbc

r = redis.Redis(host="redis", port=6379, decode_responses=True)

conn_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver;"
    "DATABASE=soporte;"
    "UID=batch_user;"
    "PWD=Batch123!;"
    "TrustServerCertificate=yes;"
)

print("Batch Worker iniciado...")

while True:
    tarea = r.blpop("cola_batch", timeout=5)

    if tarea:
        _, ticket_id = tarea
        print(f"Procesando ticket {ticket_id}")

        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO Interacciones (ticket_id, mensaje) VALUES (?, ?)",
                int(ticket_id), "Procesado por batch"
            )
            conn.commit()

    time.sleep(1)
