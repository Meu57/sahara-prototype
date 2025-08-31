# backend/app.py
import os
import datetime
import threading
import uuid
import logging
from flask import Flask, request, jsonify

# --- Configuration ---
PROJECT_ID = "sahara-wellness-prototype"
LOCATION = "asia-south1"
MODEL_NAME = "gemini-1.5-pro"

# --- App init ---
app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Lazy-initialized globals
db = None
FIRESTORE = None  # will hold the firestore module once initialized
_vertex_initialized = False
_model = None

def init_firestore():
    """Initialize Firestore client lazily and capture the firestore module."""
    global db, FIRESTORE
    if db is not None:
        return
    try:
        from google.cloud import firestore as firestore_module  # local import to avoid heavy startup cost
        FIRESTORE = firestore_module
        db = firestore_module.Client(project=PROJECT_ID)
        app.logger.info("✅ Firestore client initialized.")
    except Exception as e:
        app.logger.exception("Failed to initialize Firestore: %s", e)
        db = None
        FIRESTORE = None

def init_vertex_basic():
    """Initialize Vertex AI basics (do NOT instantiate the heavy model here)."""
    global _vertex_initialized
    if _vertex_initialized:
        return
    try:
        import vertexai  # local import
        vertexai.init(project=PROJECT_ID, location=LOCATION)
        _vertex_initialized = True
        app.logger.info("✅ Vertex AI basic initialized.")
    except Exception as e:
        app.logger.exception("Failed to initialize Vertex AI basics: %s", e)
        _vertex_initialized = False

def ensure_model():
    """Instantiate the GenerativeModel only when we actually need it (lazy)."""
    global _model
    if _model is not None:
        return
    try:
        # import and instantiate only when required
        from vertexai.generative_models import GenerativeModel
        _model = GenerativeModel(MODEL_NAME)
        app.logger.info("✅ Vertex GenerativeModel instantiated.")
    except Exception as e:
        app.logger.exception("Failed to instantiate Vertex model: %s", e)
        _model = None

def init_services_lightweight():
    """Call this at start of request handlers to ensure clients are ready (lightweight)."""
    init_firestore()
    init_vertex_basic()
    # do not call ensure_model() here to keep startup light — do it on-demand

# --- Middleware / helpers ---
def require_api_key_and_quota(flask_request):
    """
    Ensure service is ready, validate API key and increment daily usage in a Firestore transaction.
    Returns: (True, None) on success or (False, (message, status_code)) on failure.
    """
    init_services_lightweight()
    if not db:
        return False, ("Server is not properly initialized.", 503)

    api_key = flask_request.headers.get("x-api-key")
    if not api_key:
        return False, ("API key is missing.", 401)

    key_ref = db.collection("api_keys").document(api_key)
    today_str = datetime.date.today().isoformat()

    try:
        # Use the documented transactional pattern for google-cloud-firestore
        from google.cloud import firestore  # local import for decorator

        @firestore.transactional
        def _update_usage_in_transaction(transaction, key_ref, today_str):
            key_snapshot = key_ref.get(transaction=transaction)
            if not key_snapshot.exists:
                # invalid key
                return {"ok": False, "error": ("Invalid API key.", 403)}

            key_data = key_snapshot.to_dict() or {}
            daily_limit = key_data.get("daily_limit", 50)
            usage = key_data.get("usage", 0)
            last_used = key_data.get("last_used", "")

            # reset usage if it's a new day
            if last_used < today_str:
                usage = 0

            if usage >= daily_limit:
                return {"ok": False, "error": ("API quota for this key has been exceeded for today.", 429)}

            # perform the transactional update
            transaction.update(key_ref, {
                "usage": usage + 1,
                "last_used": today_str
            })
            return {"ok": True}

        # create a Transaction object from the already-initialized client and call the transactional function
        txn = db.transaction()
        result = _update_usage_in_transaction(txn, key_ref, today_str)

        if isinstance(result, dict) and not result.get("ok", False):
            return False, result["error"]

        return True, None

    except Exception as e:
        app.logger.exception("Error during Firestore transaction: %s", e)
        return False, ("Internal server error during quota check.", 500)

# --- Background memory summarization (runs async) ---
def update_memory_summary_in_background(user_id, prev_memory, user_message, ai_reply):
    app.logger.info("Starting background memory update for user: %s", user_id)
    try:
        init_vertex_basic()
        ensure_model()
        if _model is None:
            app.logger.warning("Model unavailable; skipping background memory update.")
            return

        summarization_prompt = (
            "You are a concise memory summarizer. From the PREVIOUS MEMORY and the LATEST EXCHANGE, "
            "produce a ONE-SENTENCE summary (15-25 words) capturing the key themes, user's emotional state, "
            "or important facts the companion should remember. Output only the sentence.\n\n"
            f"PREVIOUS MEMORY: {prev_memory}\n"
            f"LATEST EXCHANGE:\nUser: {user_message}\nAastha: {ai_reply}\n\n"
            "UPDATED ONE-SENTENCE SUMMARY:"
        )
        response = _model.generate_content([summarization_prompt])
        new_summary = getattr(response, "text", "").strip().replace("\n", " ")
        if not new_summary:
            app.logger.warning("Empty summary from model.")
            return

        init_services_lightweight()
        if not db:
            app.logger.warning("Firestore unavailable; cannot save memory summary.")
            return

        user_ref = db.collection("users").document(user_id)
        ts = FIRESTORE.SERVER_TIMESTAMP if FIRESTORE is not None else None
        user_ref.set({
            "memory_summary": new_summary,
            "last_memory_update": ts
        }, merge=True)
        app.logger.info("Memory update saved for %s: %s", user_id, new_summary)
    except Exception as e:
        app.logger.exception("CRITICAL ERROR in background memory update for %s: %s", user_id, e)

# --- Endpoints ---
@app.route("/")
def index():
    return "Sahara Backend is healthy.", 200

@app.route("/chat", methods=["POST"])
def handle_chat():
    init_services_lightweight()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        message, code = info
        return jsonify({"error": message}), code

    # ensure model only when needed (this reduces startup memory footprint)
    init_vertex_basic()
    ensure_model()
    if _model is None:
        return jsonify({"reply": "AI Service not available."}), 503

    data = request.json or {}
    user_message = data.get("message", "")
    user_id = data.get("userId")
    created_new_user = False
    memory_summary = ""

    if not user_id:
        user_id = str(uuid.uuid4())
        created_new_user = True
        app.logger.info("Generated new user id: %s", user_id)

    # Firestore user bookkeeping (best-effort)
    try:
        init_services_lightweight()
        if db:
            user_ref = db.collection("users").document(user_id)
            user_doc = user_ref.get()
            if not user_doc.exists:
                ts = FIRESTORE.SERVER_TIMESTAMP if FIRESTORE is not None else None
                user_ref.set({
                    "created_at": ts,
                    "memory_summary": "",
                    "conversation_count": 1
                })
                memory_summary = ""
            else:
                inc = FIRESTORE.Increment(1) if FIRESTORE is not None else None
                update_payload = {
                    "last_active": FIRESTORE.SERVER_TIMESTAMP if FIRESTORE is not None else None,
                }
                if inc is not None:
                    update_payload["conversation_count"] = inc
                # merge update
                user_ref.set(update_payload, merge=True)
                memory_summary = user_doc.to_dict().get("memory_summary", "")
    except Exception as e:
        app.logger.exception("Warning: Failed to access/update user doc for %s: %s", user_id, e)

    system_prompt = (
        "You are Aastha, a compassionate and warm AI companion. Your approach follows a 'reflect-validate-question' loop.\n"
        "VARIATION RULES:\n"
        "- Do not always start with 'It sounds like'. Use varied phrases like 'That must feel...', 'I can hear that...', or 'I'm noticing that...'.\n"
        "- Keep responses to 2-3 concise sentences: one for reflection, one for validation, and one gentle, open question.\n"
        "- Be warm and human. Use phrases like 'I’m here with you' or 'that’s a heavy thing to carry'.\n"
    )

    default_memory_text = "This is the user's first conversation."
    context_prompt = f"REMEMBER THIS from past conversations: {memory_summary or default_memory_text}"

    full_prompt = f"{system_prompt}\n\n{context_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        response = _model.generate_content([full_prompt])
        ai_reply = getattr(response, "text", "") or "Sorry, I couldn't respond right now."

        # background memory update
        memory_thread = threading.Thread(
            target=update_memory_summary_in_background,
            args=(user_id, memory_summary, user_message, ai_reply),
            daemon=True
        )
        memory_thread.start()

        payload = {"reply": ai_reply}
        if created_new_user:
            payload["userId"] = user_id
        return jsonify(payload)

    except Exception as e:
        app.logger.exception("Error calling Vertex AI: %s", e)
        return jsonify({"reply": "I'm having a little trouble thinking right now."}), 500

@app.route("/resources", methods=["GET"])
def get_resources():
    init_services_lightweight()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        message, code = info
        return jsonify({"error": message}), code

    if not db:
        return jsonify([]), 503

    try:
        articles_ref = db.collection("articles")
        articles = [doc.to_dict() for doc in articles_ref.stream()]
        return jsonify(articles)
    except Exception as e:
        app.logger.exception("Error fetching resources: %s", e)
        return jsonify([]), 500

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    init_services_lightweight()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        message, code = info
        return jsonify({"error": message}), code

    if not db:
        return jsonify({"status": "error", "message": "Database not connected"}), 503

    data = request.json or {}
    user_id = data.get("userId")
    entry = data.get("entry")
    if not user_id or not entry:
        return jsonify({"status": "error", "message": "userId and entry are required"}), 400

    try:
        user_entries_ref = db.collection("users").document(user_id).collection("entries")
        user_entries_ref.add(entry)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        app.logger.exception("Error syncing journal: %s", e)
        return jsonify({"status": "error", "message": "Could not save entry"}), 500

@app.route("/_debug")
def debug():
    return jsonify({
        "K_REVISION": os.environ.get("K_REVISION"),
        "K_CONFIGURATION": os.environ.get("K_CONFIGURATION"),
        "K_SERVICE": os.environ.get("K_SERVICE"),
        "firestore_initialized": bool(db),
        "vertex_basic": bool(_vertex_initialized),
        "model_ready": bool(_model),
    })

if __name__ == "__main__":
    # Local debugging only
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=False)
