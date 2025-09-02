# backend/app.py
import os
import datetime
import threading
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from flask import Flask, request, jsonify
from flask_cors import CORS

# -----------------------
# Config (env overrides)
# -----------------------
PROJECT_ID = os.environ.get("PROJECT_ID", "sahara-wellness-prototype")
LOCATION = os.environ.get("LOCATION", "asia-south1")
MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-1.5-pro")
DAILY_GLOBAL_API_LIMIT = int(os.environ.get("DAILY_GLOBAL_API_LIMIT", "240"))
QUOTA_FAIL_OPEN = os.environ.get("QUOTA_FAIL_OPEN", "false").lower() in ("1", "true", "yes")
MODEL_CALL_TIMEOUT = int(os.environ.get("MODEL_CALL_TIMEOUT_SECONDS", "20"))

# -----------------------
# Globals (populated lazily)
# -----------------------
db = None
FIRESTORE = None
VERTEX = None
_vertex_initialized = False
_model = None
_model_lock = threading.Lock()

# -----------------------
# Flask app + logging
# -----------------------
app = Flask(__name__)
app = Flask(__name__) 
CORS(app)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sahara-backend")

# -----------------------
# Initialization helpers
# -----------------------
def init_firestore():
    global db, FIRESTORE
    if db is not None:
        return
    try:
        from google.cloud import firestore as firestore_module
        FIRESTORE = firestore_module
        db = firestore_module.Client(project=PROJECT_ID)
        logger.info("Firestore initialized.")
    except Exception as e:
        logger.exception("Failed to initialize Firestore: %s", e)
        db = None
        FIRESTORE = None

def init_vertex_basic():
    global _vertex_initialized, VERTEX
    if _vertex_initialized:
        return
    try:
        import vertexai
        vertexai.init(project=PROJECT_ID, location=LOCATION)
        VERTEX = vertexai
        _vertex_initialized = True
        logger.info("Vertex AI basic initialized.")
    except Exception as e:
        logger.exception("Failed to initialize Vertex AI: %s", e)
        _vertex_initialized = False
        VERTEX = None

def ensure_model():
    global _model
    if _model is not None:
        return
    with _model_lock:
        if _model is not None:
            return
        try:
            from vertexai.generative_models import GenerativeModel
            _model = GenerativeModel(MODEL_NAME)
            logger.info("Vertex GenerativeModel instantiated.")
        except Exception as e:
            logger.exception("Failed to instantiate Vertex model: %s", e)
            _model = None

def init_services_lightweight():
    init_firestore()
    init_vertex_basic()

# -----------------------
# Helpers
# -----------------------
def _normalize_last_used(last_used_value):
    if not last_used_value:
        return ""
    try:
        if hasattr(last_used_value, "to_datetime"):
            dt = last_used_value.to_datetime()
            return dt.date().isoformat()
        import datetime as _dt
        if isinstance(last_used_value, _dt.datetime):
            return last_used_value.date().isoformat()
        if isinstance(last_used_value, str):
            return last_used_value[:10]
    except Exception:
        pass
    return ""

# -----------------------
# Global quota (daily)
# -----------------------
def check_and_update_global_quota():
    init_firestore()
    if not db or FIRESTORE is None:
        logger.warning("Firestore unavailable during global quota check. Returning QUOTA_FAIL_OPEN=%s", QUOTA_FAIL_OPEN)
        return QUOTA_FAIL_OPEN

    today = datetime.date.today().isoformat()
    counter_ref = db.collection("usage_stats").document(today)
    try:
        doc = counter_ref.get()
        current = doc.to_dict().get("api_calls", 0) if doc.exists else 0
        if current >= DAILY_GLOBAL_API_LIMIT:
            logger.info("Global API limit reached: %s calls on %s", current, today)
            return False
        counter_ref.set({"api_calls": FIRESTORE.Increment(1)}, merge=True)
        return True
    except Exception as e:
        logger.exception("Error updating global quota: %s", e)
        return QUOTA_FAIL_OPEN

# -----------------------
# Per-key quota & API key enforcement (transactional)
# -----------------------
def require_api_key_and_quota(flask_request):
    init_services_lightweight()
    if not db or FIRESTORE is None:
        return False, ("Server not ready", 503)

    api_key = flask_request.headers.get("x-api-key")
    if not api_key:
        return False, ("API key is missing.", 401)

    key_ref = db.collection("api_keys").document(api_key)
    today_str = datetime.date.today().isoformat()

    def txn_logic(transaction):
        snap = key_ref.get(transaction=transaction)
        if not snap.exists:
            raise ValueError("INVALID_KEY")
        key_data = snap.to_dict() or {}
        daily_limit = int(key_data.get("daily_limit", 50))
        usage = int(key_data.get("usage", 0))
        last_used_raw = key_data.get("last_used", "")
        last_used = _normalize_last_used(last_used_raw)
        if last_used < today_str:
            usage = 0
        if usage >= daily_limit:
            raise ValueError("QUOTA_EXCEEDED")
        transaction.update(key_ref, {
            "usage": usage + 1,
            "last_used": today_str
        })
        return True

    try:
        db.run_transaction(txn_logic)
        return True, None
    except ValueError as ve:
        v = str(ve)
        if v == "INVALID_KEY":
            return False, ("Invalid API key.", 403)
        if v == "QUOTA_EXCEEDED":
            return False, ("API quota for this key has been exceeded for today.", 429)
        logger.exception("ValueError in transaction: %s", ve)
        return False, ("Internal server error during quota check.", 500)
    except Exception as e:
        logger.exception("Error during quota transaction: %s", e)
        return False, ("Internal server error during quota check.", 500)

# -----------------------
# Model generation wrapper (method probing + timeout)
# -----------------------
def _generate_text_from_model(prompt):
    if _model is None:
        return None

    candidates = ("generate_content", "generate", "generate_text", "predict")

    def _call():
        for method in candidates:
            if hasattr(_model, method):
                fn = getattr(_model, method)
                try:
                    try:
                        resp = fn([prompt])
                    except TypeError:
                        resp = fn(prompt)
                    if hasattr(resp, "text"):
                        return resp.text
                    if hasattr(resp, "result"):
                        return getattr(resp, "result")
                    return str(resp)
                except Exception as inner:
                    # debug-level log so we can inspect which candidate failed, without noisy stack each time
                    logger.debug("Model method %s raised: %s", method, inner)
                    continue
        logger.error("No working generation method found on model (tried: %s)", candidates)
        return None

    with ThreadPoolExecutor(max_workers=1) as ex:
        fut = ex.submit(_call)
        try:
            return fut.result(timeout=MODEL_CALL_TIMEOUT)
        except FuturesTimeoutError:
            # timeout is expected sometimes; warn rather than exception to avoid noisy error-dumps
            logger.warning("Model call timed out after %s seconds", MODEL_CALL_TIMEOUT)
            return None
        except Exception as e:
            logger.exception("Unexpected error calling model: %s", e)
            return None

# -----------------------
# Background memory summarization (best-effort)
# -----------------------
def update_memory_summary_in_background(user_id, prev_memory, user_message, ai_reply):
    logger.info("Starting background memory update for user: %s", user_id)
    try:
        init_vertex_basic()
        ensure_model()
        if _model is None or not db or FIRESTORE is None:
            logger.warning("Skipping memory update: model/firestore not available.")
            return

        summarization_prompt = (
            "You are a concise memory summarizer. From the PREVIOUS MEMORY and the LATEST EXCHANGE, "
            "produce a ONE-SENTENCE summary (15-25 words) capturing the key themes, user's emotional state, "
            "or important facts the companion should remember. Output only the sentence.\n\n"
            f"PREVIOUS MEMORY: {prev_memory}\n"
            f"LATEST EXCHANGE:\nUser: {user_message}\nAastha: {ai_reply}\n\n"
            "UPDATED ONE-SENTENCE SUMMARY:"
        )

        new_summary = _generate_text_from_model(summarization_prompt)
        if not new_summary:
            logger.warning("Memory summarization returned empty result.")
            return

        user_ref = db.collection("users").document(user_id)
        user_ref.set({
            "memory_summary": new_summary,
            "last_memory_update": FIRESTORE.SERVER_TIMESTAMP
        }, merge=True)
        logger.info("Saved memory summary for user: %s", user_id)
    except Exception as e:
        logger.exception("CRITICAL ERROR in background memory update for %s: %s", user_id, e)

# -----------------------
# Endpoints
# -----------------------
@app.route("/")
def index():
    return "Sahara Backend is healthy.", 200

@app.route("/chat", methods=["POST"])
def handle_chat():
    init_services_lightweight()

    if not check_and_update_global_quota():
        return jsonify({"reply": "Aastha is resting. Please check back tomorrow."}), 503

    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    init_vertex_basic()
    ensure_model()
    if _model is None:
        return jsonify({"reply": "AI Service not available."}), 503

    data = request.get_json(silent=True) or {}
    user_message = data.get("message", "")
    user_id = data.get("userId")
    created_new_user = False
    memory_summary = ""

    if not user_id:
        user_id = str(uuid.uuid4())
        created_new_user = True

    try:
        init_firestore()
        if db:
            user_ref = db.collection("users").document(user_id)
            user_doc = user_ref.get()
            if not user_doc.exists:
                user_ref.set({
                    "created_at": FIRESTORE.SERVER_TIMESTAMP,
                    "memory_summary": "",
                    "conversation_count": 1
                })
                memory_summary = ""
            else:
                user_ref.set({
                    "last_active": FIRESTORE.SERVER_TIMESTAMP,
                    "conversation_count": FIRESTORE.Increment(1)
                }, merge=True)
                memory_summary = user_doc.to_dict().get("memory_summary", "")
    except Exception as e:
        logger.exception("Warning: Failed to access/update user doc for %s: %s", user_id, e)

    system_prompt = (
        "You are Aastha, a compassionate and warm AI companion. Keep replies concise (2-3 sentences) "
        "using reflect-validate-question structure."
    )
    default_memory_text = "This is the user's first conversation."
    context_prompt = f"REMEMBER THIS from past conversations: {memory_summary or default_memory_text}"
    full_prompt = f"{system_prompt}\n\n{context_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        ai_reply = _generate_text_from_model(full_prompt) or "Sorry, I couldn't respond right now."

        t = threading.Thread(
            target=update_memory_summary_in_background,
            args=(user_id, memory_summary, user_message, ai_reply),
            daemon=True
        )
        t.start()

        payload = {"reply": ai_reply}
        if created_new_user:
            payload["userId"] = user_id
        return jsonify(payload)
    except Exception as e:
        logger.exception("Error handling chat: %s", e)
        return jsonify({"reply": "I'm having a little trouble thinking right now."}), 500

@app.route("/resources", methods=["GET"])
def get_resources():
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    if not db:
        return jsonify([]), 503

    limit = request.args.get("limit", default=100, type=int)
    try:
        resources_ref = db.collection("resources").limit(limit)
        docs = resources_ref.stream()
        resources = [{**doc.to_dict(), "id": doc.id} for doc in docs]
        return jsonify(resources)
    except Exception as e:
        logger.exception("Error fetching resources: %s", e)
        return jsonify([]), 500

@app.route("/resources/<resource_id>", methods=["GET"])
def get_resource(resource_id):
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    try:
        doc = db.collection("resources").document(resource_id).get()
        if doc.exists:
            return jsonify({**doc.to_dict(), "id": doc.id})
        return jsonify({"error": "Resource not found"}), 404
    except Exception as e:
        logger.exception("Error retrieving resource %s: %s", resource_id, e)
        return jsonify({"error": "Internal server error"}), 500

@app.route("/resources", methods=["POST"])
def create_resource():
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Missing/invalid JSON body"}), 400
    try:
        new_ref = db.collection("resources").document()
        new_ref.set(data)
        return jsonify({"id": new_ref.id, **data}), 201
    except Exception as e:
        logger.exception("Error creating resource: %s", e)
        return jsonify({"error": "Could not create resource"}), 500

@app.route("/resources/<resource_id>", methods=["PUT"])
def update_resource(resource_id):
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Missing/invalid JSON body"}), 400
    try:
        doc_ref = db.collection("resources").document(resource_id)
        if not doc_ref.get().exists:
            return jsonify({"error": "Resource not found"}), 404
        doc_ref.update(data)
        return jsonify({"id": resource_id, **data}), 200
    except Exception as e:
        logger.exception("Error updating resource %s: %s", resource_id, e)
        return jsonify({"error": "Could not update resource"}), 500

@app.route("/resources/<resource_id>", methods=["DELETE"])
def delete_resource(resource_id):
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    try:
        doc_ref = db.collection("resources").document(resource_id)
        if not doc_ref.get().exists:
            return jsonify({"error": "Resource not found"}), 404
        doc_ref.delete()
        return jsonify({"message": "Resource deleted"}), 200
    except Exception as e:
        logger.exception("Error deleting resource %s: %s", resource_id, e)
        return jsonify({"error": "Could not delete resource"}), 500

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    data = request.get_json(silent=True) or {}
    user_id = data.get("userId")
    entry = data.get("entry")
    if not user_id or entry is None:
        return jsonify({"status": "error", "message": "userId and entry are required"}), 400

    # FRIEND SUGGESTION APPLIED: coerce string entries to dict
    if not isinstance(entry, dict):
        entry = {"text": entry}

    try:
        db.collection("users").document(user_id).collection("entries").add(entry)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logger.exception("Error syncing journal: %s", e)
        return jsonify({"status": "error", "message": "Could not save entry"}), 500

@app.route("/_debug")
def debug():
    init_services_lightweight()
    return jsonify({
        "K_REVISION": os.environ.get("K_REVISION"),
        "K_CONFIGURATION": os.environ.get("K_CONFIGURATION"),
        "K_SERVICE": os.environ.get("K_SERVICE"),
        "firestore_initialized": bool(db),
        "vertex_basic": bool(_vertex_initialized),
        "model_ready": bool(_model),
        "quota_fail_open": QUOTA_FAIL_OPEN
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=False)
