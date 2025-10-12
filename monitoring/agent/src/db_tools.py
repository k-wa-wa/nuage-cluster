import os
import psycopg2
from pydantic import BaseModel, Field
from langchain.tools import tool


def get_db_connection():
    """Establishes and returns a PostgreSQL database connection."""
    try:
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            database=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"]
        )
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        raise


class ReportInput(BaseModel):
    """Input schema for the insert_report tool."""
    report_name: str = Field(description="The name of the report.")
    report_type: str = Field(
        description="The type of the report (e.g., 'daily', 'weekly', 'monthly', 'on-demand')."
    )
    content: str = Field(
        description="The content of the report as a string (e.g., summary text, raw data)."
    )
    status: str = Field(description="The status of the report (e.g., 'pending', 'completed', 'failed').")


@tool("insert_report", args_schema=ReportInput)
def insert_report(report_name: str, report_type: str, content: str, status: str) -> str:
    """
    Inserts a new report into the 'reports' PostgreSQL table.

    Args:
        report_name: The name of the report.
        report_type: The type of the report (e.g., 'daily', 'weekly', 'monthly', 'on-demand').
        content: The content of the report as a string.
        status: The status of the report (e.g., 'pending', 'completed', 'failed').

    Returns:
        report_id: The id of the report
    """
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO reports (report_name, report_type, content, status)
            VALUES (%s, %s, %s, %s)
            RETURNING report_id;
            """,
            (report_name, report_type, content, status)
        )
        row = cur.fetchone()
        if row is None:
            raise Exception("Failed to retrieve report_id after insertion.")
        report_id = row[0]
        conn.commit()
        cur.close()
        return report_id
    except Exception as e:
        print(e)
        if conn:
            conn.rollback()
        return ""
    finally:
        if conn:
            conn.close()
