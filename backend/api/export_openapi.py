import json
import os
from backend.main import app

def export_openapi():
    """Extracts the OpenAPI schema from the FastAPI app and saves it to openapi.json."""
    openapi_schema = app.openapi()
    output_file = os.path.join(os.getcwd(), "openapi.json")
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(openapi_schema, f, indent=2)
    print(f"Successfully exported OpenAPI spec to {output_file}")

if __name__ == "__main__":
    export_openapi()