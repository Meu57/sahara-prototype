from flask import Flask, request, jsonify
from google.cloud import firestore
from datetime import datetime
import logging

app = Flask(__name__)
db = firestore.Client()

# --- Quota & API Key Enforcement ---
def require_api_key_and_quota():
    api_key = request.headers.get("x-api-key")
    if not api_key:
        return False, ("Missing API key.", 401)

    key_ref = db.collection("api_keys").document(api_key)
    today_str = datetime.utcnow().strftime("%Y-%m-%d")

    try:
        @firestore.transactional
        def update_usage_in_transaction(transaction):
            key_snapshot = key_ref.get(transaction=transaction)
            if not key_snapshot.exists:
                return {"ok": False, "error": ("Invalid API key.", 403)}

            key_data = key_snapshot.to_dict() or {}
            daily_limit = key_data.get("daily_limit", 50)
            usage = key_data.get("usage", 0)
            last_used = key_data.get("last_used", "")

            # Reset usage count if this is a new day
            if last_used < today_str:
                usage = 0

            # Enforce quota
            if usage >= daily_limit:
                return {"ok": False, "error": ("API quota for this key has been exceeded for today.", 429)}

            # Update document atomically
            transaction.update(key_ref, {
                "usage": usage + 1,
                "last_used": today_str
            })
            return {"ok": True}

        result = update_usage_in_transaction(db.transaction())

        if isinstance(result, dict) and not result.get("ok", False):
            return False, result["error"]
        return True, None

    except Exception as e:
        logging.exception("Error during Firestore transaction")
        return False, ("Internal Server Error", 500)


# --- Routes ---
@app.route("/resources", methods=["GET"])
def get_resources():
    ok, error = require_api_key_and_quota()
    if not ok:
        return jsonify({"error": error[0]}), error[1]

    limit = request.args.get("limit", default=100, type=int)
    resources_ref = db.collection("resources").limit(limit)
    docs = resources_ref.stream()
    resources = [{**doc.to_dict(), "id": doc.id} for doc in docs]
    return jsonify(resources)


@app.route("/resources/<resource_id>", methods=["GET"])
def get_resource(resource_id):
    ok, error = require_api_key_and_quota()
    if not ok:
        return jsonify({"error": error[0]}), error[1]

    resource_ref = db.collection("resources").document(resource_id)
    doc = resource_ref.get()
    if doc.exists:
        return jsonify({**doc.to_dict(), "id": doc.id})
    return jsonify({"error": "Resource not found"}), 404


@app.route("/resources", methods=["POST"])
def create_resource():
    ok, error = require_api_key_and_quota()
    if not ok:
        return jsonify({"error": error[0]}), error[1]

    data = request.get_json()
    if not data:
        return jsonify({"error": "Missing request body"}), 400

    resources_ref = db.collection("resources")
    new_doc_ref = resources_ref.document()
    new_doc_ref.set(data)
    return jsonify({"id": new_doc_ref.id, **data}), 201


@app.route("/resources/<resource_id>", methods=["PUT"])
def update_resource(resource_id):
    ok, error = require_api_key_and_quota()
    if not ok:
        return jsonify({"error": error[0]}), error[1]

    data = request.get_json()
    if not data:
        return jsonify({"error": "Missing request body"}), 400

    resource_ref = db.collection("resources").document(resource_id)
    if not resource_ref.get().exists:
        return jsonify({"error": "Resource not found"}), 404

    resource_ref.update(data)
    return jsonify({"id": resource_id, **data})


@app.route("/resources/<resource_id>", methods=["DELETE"])
def delete_resource(resource_id):
    ok, error = require_api_key_and_quota()
    if not ok:
        return jsonify({"error": error[0]}), error[1]

    resource_ref = db.collection("resources").document(resource_id)
    if not resource_ref.get().exists:
        return jsonify({"error": "Resource not found"}), 404

    resource_ref.delete()
    return jsonify({"message": "Resource deleted"})


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8080)
