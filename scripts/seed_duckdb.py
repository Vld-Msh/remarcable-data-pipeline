"""
seed_duckdb.py — loads the raw CSV files into DuckDB so dbt sources resolve.
Run before `dbt run` in local/CI environments.

Usage:
    python scripts/seed_duckdb.py --db dev.duckdb --csv-dir ../
"""

import argparse
import duckdb
from pathlib import Path

TABLES = {
    "orders":      "orders.csv",
    "contractors": "contractors.csv",
    "order_items": "order_items.csv",
}

def seed(db_path: str, csv_dir: Path):
    con = duckdb.connect(db_path)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")

    for table, filename in TABLES.items():
        csv_path = csv_dir / filename
        if not csv_path.exists():
            raise FileNotFoundError(f"CSV not found: {csv_path}")

        con.execute(f"DROP TABLE IF EXISTS raw.{table}")
        con.execute(f"""
            CREATE TABLE raw.{table} AS
            SELECT * FROM read_csv_auto('{csv_path}', header=true)
        """)
        count = con.execute(f"SELECT count(*) FROM raw.{table}").fetchone()[0]
        print(f"  Loaded raw.{table}: {count} rows from {filename}")

    con.close()
    print(f"\nDone — DuckDB seeded at {db_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db",      default="dev.duckdb",      help="DuckDB file path")
    parser.add_argument("--csv-dir", default="..",              help="Directory containing CSV files")
    args = parser.parse_args()
    seed(args.db, Path(args.csv_dir))
