"""Run schema/seed/mutation SQL inside private RDS from a Glue VPC job.

This avoids requiring a developer workstation to reach the private subnet.
The SQL files are immutable, Terraform-managed artifacts in the control
bucket; credentials are read at runtime from the Terraform-managed secret.
"""

from __future__ import annotations

import json
import re
import sys

import boto3
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession


def _sql_statements(text: str) -> list[str]:
    return [statement.strip() for statement in text.split(";") if statement.strip()]


def main() -> None:
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "RDS_SECRET_ARN",
            "RDS_JDBC_URL",
            "CONTROL_BUCKET",
            "SCHEMA_SQL_KEY",
            "SEED_SQL_KEY",
            "MUTATION_SQL_KEY",
            "SLOT_NAME",
            "ACTION",
        ],
    )
    secrets = boto3.client("secretsmanager")
    secret = json.loads(secrets.get_secret_value(SecretId=args["RDS_SECRET_ARN"])["SecretString"])
    s3 = boto3.client("s3")
    sql_keys = {
        "schema_seed": [args["SCHEMA_SQL_KEY"], args["SEED_SQL_KEY"]],
        "mutations": [args["MUTATION_SQL_KEY"]],
    }
    if args["ACTION"] not in {*sql_keys, "create_slot"}:
        raise ValueError("ACTION must be schema_seed, mutations, or create_slot")

    spark = SparkSession.builder.getOrCreate()
    jvm = spark.sparkContext._gateway.jvm
    connection = jvm.java.sql.DriverManager.getConnection(
        args["RDS_JDBC_URL"], secret["username"], secret["password"]
    )
    try:
        statement = connection.createStatement()
        if args["ACTION"] == "create_slot":
            slot_name = args["SLOT_NAME"]
            if not re.fullmatch(r"[a-z0-9_]+", slot_name):
                raise ValueError("SLOT_NAME contains invalid characters")
            result = statement.executeQuery(
                f"SELECT 1 FROM pg_replication_slots WHERE slot_name = '{slot_name}'"
            )
            exists = result.next()
            result.close()
            if not exists:
                statement.execute(
                    f"SELECT * FROM pg_create_logical_replication_slot('{slot_name}', 'test_decoding')"
                )
        else:
            for key in sql_keys[args["ACTION"]]:
                body = s3.get_object(Bucket=args["CONTROL_BUCKET"], Key=key)["Body"].read().decode("utf-8")
                for sql in _sql_statements(body):
                    statement.execute(sql)
        statement.close()
    finally:
        connection.close()
        spark.stop()


if __name__ == "__main__":
    main()
