#!/usr/bin/env python3
import json
import sys
from jsonschema import validate, ValidationError

schema_path = 'schema/sales-palyoad-schema.json'
data_path = 'test/data-sales.ndjson'

# Load schema
with open(schema_path, encoding='utf-8') as f:
  schema = json.load(f)

# Counters
total = 0
passed = 0
failed = 0

# Open NDJSON and validate
with open(data_path, encoding='utf-8') as f:
  for i, line in enumerate(f, start=1):
    total += 1
    try:
      row = json.loads(line)
      payload = row.get("payload")
      if payload is None:
        print(f"[Line {i}] ERROR: No payload found")
        failed += 1
        continue

      validate(instance=payload, schema=schema)
      passed += 1

    except ValidationError as ve:
      print(f"[Line {i}] Validation error: {ve.message}")
      failed += 1
    except Exception as e:
      print(f"[Line {i}] General error: {e}")
      failed += 1

# Summary
print("\n--- Validation Summary ---")
print(f"Total records : {total}")
print(f"Valid         : {passed}")
print(f"Invalid       : {failed}")

# Exit code: 0 if all passed, 1 otherwise
sys.exit(0 if failed == 0 else 1)
