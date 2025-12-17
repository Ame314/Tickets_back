import os
import time
import redis
import pyodbc

r = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    decode_responses=True,
)

conn_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={os.getenv('DATABASE_HOST', 'sqlserver')},{os.getenv('DATABASE_PORT', '1433')};"
    f"DATABASE={os.getenv('DATABASE_NAME', 'soporte')};"
    f"UID={os.getenv('DATABASE_USER', 'sa')};"
    f"PWD={os.getenv('DATABASE_PASSWORD', 'P@ssw0rd12345!')};"
    "Encrypt=yes;"
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
