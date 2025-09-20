# backend/app.py
import os
import threading
import uuid
import logging
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from datetime import date,datetime,timezone, timedelta
from google.cloud import firestore as firestore_module
from google.api_core import exceptions as google_exceptions
FIRESTORE = firestore_module  # Only for SERVER_TIMESTAMP
from flask import Flask, request, jsonify
from flask_cors import CORS
import random   

SUGGESTION_MAP = {
    "stress": {
        "title": "Try a 5-minute breathing exercise",
        "resource_id": "PBMtCFmQdfa2IRoBB46"
    },
    "anxious": {
        "title": "Try a 5-minute breathing exercise",
        "resource_id": "PBMtCFmQdfa2IRoBB46" # same as stress
    }
}

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
VERTEX = None
_vertex_initialized = False
_model = None
_model_lock = threading.Lock()

# -----------------------
# Flask app + logging
# -----------------------
app = Flask(__name__)
CORS(app)  # keep this; we also add explicit after_request headers below
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sahara-backend")

# -----------------------
# Ensure CORS headers on every response (explicit, hackathon-safe)
# -----------------------
@app.after_request
def add_cors_headers(response):
    # For the hackathon/demo: using '*' is simplest. In production, replace '*' with your frontend origin.
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS, PUT, DELETE"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, x-api-key, Authorization"
    response.headers["Access-Control-Expose-Headers"] = "Content-Type, x-api-key"
    return response

# Generic OPTIONS responder (ensures preflight receives 204)
@app.route("/", methods=["OPTIONS"])
def options_root():
    return ("", 204)

@app.route("/<path:path>", methods=["OPTIONS"])
def options(path):
    return ("", 204)

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

    today = date.today().isoformat()
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
# PASTE THIS NEW CODE INTO YOUR app.py  
# Replace your _transactional_key_update + require_api_key_and_quota with this version. 
# transactional pattern compatible with google-cloud-firestore v2.x
def _transactional_key_update(transaction, key_ref, today_str):
    """
    Runs inside a transaction (transaction passed by the decorator).
    """
    key_snapshot = key_ref.get(transaction=transaction)
    if not key_snapshot.exists:
        raise google_exceptions.NotFound("Invalid API key.")

    key_data = key_snapshot.to_dict() or {}
    daily_limit = int(key_data.get("quota_daily", 50))
    usage_today = int(key_data.get("used_today", 0))
    last_used_str = _normalize_last_used(key_data.get("last_used"))

    # reset if new day
    if last_used_str < today_str:
        usage_today = 0

    if usage_today >= daily_limit:
        raise ValueError("API quota for this key has been exceeded.")

    # atomic update inside the transaction
    transaction.update(key_ref, {
        "used_today": usage_today + 1,
        "last_used": FIRESTORE.SERVER_TIMESTAMP
    })
    return True 

def require_api_key_and_quota(flask_request):
    logger.info("--- Starting API Key Check ---")

    if flask_request.method == "OPTIONS":
        return True, None

    init_services_lightweight()
    if not db or FIRESTORE is None:
        logger.error("API Key Check failed: Firestore (db) is not initialized.")
        return False, ("Server not ready to validate key", 503)

    api_key = flask_request.headers.get("x-api-key")
    if not api_key:
        logger.warning("API Key Check failed: Header 'x-api-key' is missing.")
        return False, ("API key is missing.", 401)

    logger.info(f"Found API key: ...{api_key[-4:]}")

    key_ref = db.collection("api_keys").document(api_key)
    today_str = date.today().isoformat()

    try:
        # create a transaction object
        transaction = db.transaction()
        # decorate the function for transactional execution (FIRESTORE is the module)
        transactional_fn = FIRESTORE.transactional(_transactional_key_update)
        # call the transactional function, passing the transaction object
        transactional_fn(transaction, key_ref, today_str)

        logger.info("--- API Key Check Successful ---")
        return True, None

    except google_exceptions.NotFound:
        logger.warning(f"API Key not found in Firestore: ...{api_key[-4:]}")
        return False, ("Invalid API key.", 403)

    except ValueError as e:
        logger.warning(f"Quota exceeded for key ...{api_key[-4:]}: {e}")
        return False, (str(e), 429)

    except google_exceptions.Aborted as e:
        # Aborted can happen under contention; one retry attempt
        logger.info("Transaction aborted, retrying once for key ...%s: %s", api_key[-4:], e)
        try:
            transaction = db.transaction()
            transactional_fn(transaction, key_ref, today_str)
            logger.info("Transaction retry successful for key ...%s", api_key[-4:])
            return True, None
        except Exception as e2:
            logger.exception("Transaction retry failed for key ...%s: %s", api_key[-4:], e2)
            return False, ("Internal server error during quota check.", 500)

    except Exception as e:
        logger.exception(f"CRITICAL UNEXPECTED ERROR during quota check for key ...{api_key[-4:]}: {e}")
        return False, ("Internal server error during quota check.", 500)

# -----------------------
# Robust model caller and chat handler
# -----------------------

def _generate_text_from_model(prompt):
    """
    Robust model caller: probe common SDK method names, apply timeout,
    handle errors gracefully and return a simple string (or None).
    """
    global _model
    if _model is None:
        logger.warning("_generate_text_from_model called but model is not initialized.")
        return None

    candidates = ("generate_content", "generate", "generate_text", "predict")

    def _call():
        for method in candidates:
            if hasattr(_model, method):
                fn = getattr(_model, method)
                try:
                    # Try both list and single-string signatures
                    try:
                        resp = fn([prompt])
                    except TypeError:
                        resp = fn(prompt)
                    # Read common response shapes
                    if hasattr(resp, "text"):
                        return resp.text
                    if hasattr(resp, "result"):
                        return getattr(resp, "result")
                    return str(resp)
                except Exception as inner:
                    logger.debug("Model method %s raised: %s", method, inner)
                    continue
        logger.error("No working generation method found on model (tried: %s)", candidates)
        return None

    with ThreadPoolExecutor(max_workers=1) as ex:
        fut = ex.submit(_call)
        try:
            return fut.result(timeout=MODEL_CALL_TIMEOUT)
        except FuturesTimeoutError:
            logger.warning("Model call timed out after %s seconds", MODEL_CALL_TIMEOUT)
            return None
        except Exception as e:
            logger.exception("Unexpected error calling model: %s", e)
            return None 

def _few_shot_for_tone(tone: str) -> str:
    """Return a few-shot examples block for the requested tone."""
    t = (tone or "empathy").lower()
    if t == "short_advice":
        return (
            "\n\nEXAMPLES (Short Advice):\n"
            "User: I'm overwhelmed with work and can't focus.\n"
            "Aastha: Try a 10-minute break and one focused task. Which task feels smallest?\n\n"
            "User: I can't sleep at night.\n"
            "Aastha: Try a short wind-down (no screens) tonight. Want a breathing prompt?\n\n"
        )
    if t == "coaching":
        return (
            "\n\nEXAMPLES (Coaching):\n"
            "User: I feel anxious about public speaking.\n"
            "Aastha: That’s common — let’s break it down. What’s one small step you could practice today?\n\n"
            "User: I want to make more friends but don't know where to start.\n"
            "Aastha: Pick one low-pressure activity to try this week. What interests you most?\n\n"
        )
    # default: empathy
    return (
        "\n\nEXAMPLES (Empathy):\n"
        "User: I'm feeling lonely and I don't have friends.\n"
        "Aastha: I'm sorry you're feeling lonely — that must be hard. Would you like to tell me about a time you felt understood?\n\n"
        "User: I get really nervous in groups.\n"
        "Aastha: That makes sense; groups can feel intense. What's one small thing that feels okay during a social moment?\n\n"
    )

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

#Chat endpoint
@app.route("/chat", methods=["POST", "OPTIONS"])
def handle_chat():
    # Allow preflight
    if request.method == "OPTIONS":
        return ("", 204)

    # API key and quota check
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    init_services_lightweight()
    ensure_model()

    # Quick readiness checks
    if _model is None:
        return jsonify({"reply": "AI Service is currently unavailable."}), 503

    if not check_and_update_global_quota():
        return jsonify({"reply": "Aastha is resting. Please check back tomorrow."}), 503

    data = request.get_json(silent=True) or {}
    user_message = (data.get("message") or "").strip()
    user_id = data.get("userId")
    created_new_user = False
    memory_summary = ""
    is_new_conversation = True  # default assumption

    if not user_id:
        user_id = str(uuid.uuid4())
        created_new_user = True

    # Read user memory and last_active timestamp
    try:
        init_firestore()
        if db:
            user_ref = db.collection("users").document(user_id)
            user_doc = user_ref.get()
            if user_doc.exists:
                user_data = user_doc.to_dict()
                memory_summary = user_data.get("memory_summary", "")
                last_active_dt = user_data.get("last_active")

                if last_active_dt:
                    time_since_last_active = datetime.now(timezone.utc) - last_active_dt
                    if time_since_last_active < timedelta(minutes=30):
                        is_new_conversation = False
    except Exception as e:
        logger.exception("Warning: Could not fetch user doc for %s: %s", user_id, e)

    # Choose tone
    requested_tone = (data.get("tone") or "").strip().lower()
    if requested_tone not in ("empathy", "short_advice", "coaching"):
        requested_tone = random.choice(["empathy", "short_advice", "coaching"])
    few_shot = _few_shot_for_tone(requested_tone)

    system_prompt = (
        "You are Aastha — a warm, compassionate AI companion... Always reflect, validate, and ask one open question."
        "**If the user says they don't understand or that their English isn't good, simplify your language,"
        "use shorter sentences, and ask them to explain what is confusing.**"
    )

    # Build prompt based on session freshness - UPDATED LOGIC
    default_memory_text = "This is the user's first conversation. Greet them warmly if appropriate."
    context_prompt = f"PAST MEMORY: {memory_summary or default_memory_text}"
    full_prompt = f"{system_prompt}\n{few_shot}\n{context_prompt}\n\nUser: {user_message}\nAastha:"

    # Call model
    ai_reply = _generate_text_from_model(full_prompt)

    payload = {}  # Initialize an empty payload dictionary

    # ✅ --- START: CORRECTED LOGIC --- ✅
    if ai_reply:
        # SUCCESS PATH
        payload["reply"] = ai_reply 

        # Only inspect the user's message for suggestion keywords
        user_text_lower = (user_message or "").lower()
        for keyword, suggestion_data in SUGGESTION_MAP.items():
            if keyword in user_text_lower:
                payload["suggestion"] = suggestion_data
                ai_reply += f"\n\n{suggestion_data['title']}. Would you like to add it to your Journey?"
                payload["reply"] = ai_reply  # Update payload with appended text
                break

        # Launch background memory update
        try:
            threading.Thread(
                target=update_memory_summary_in_background,
                args=(user_id, memory_summary, user_message, ai_reply),
                daemon=True
            ).start()
        except Exception:
            logger.exception("Failed to start memory update thread for %s", user_id)

    else:
        # FAILURE PATH
        fallback_reply = (
            "Thank you for telling me that. I'm here for you. Would you like to tell me more about how that feels?"
        )
        payload["reply"] = fallback_reply
        # No suggestion logic in failure path
    # ✅ --- END: CORRECTED LOGIC --- ✅

    if created_new_user:
        payload["userId"] = user_id

    # Update Firestore user doc
    try:
        if db and FIRESTORE is not None:
            user_ref = db.collection("users").document(user_id)
            user_ref.set({
                "last_active": FIRESTORE.SERVER_TIMESTAMP,
                "conversation_count": FIRESTORE.Increment(1)
            }, merge=True)
    except Exception as e:
        logger.exception("Warning: Failed to update user doc post-chat for %s: %s", user_id, e)

    return jsonify(payload)

@app.route("/resources", methods=["GET"])
def get_resources():
    init_firestore()

    # --- ADD THIS CHECK ---
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    # ----------------------

    if not db:
        return jsonify([]), 503

    limit = request.args.get("limit", default=100, type=int)
    try:
        resources_ref = db.collection("articles").limit(limit)
        docs = resources_ref.stream()
        resources = [{**doc.to_dict(), "id": doc.id} for doc in docs]
        return jsonify(resources)
    except Exception as e:
        logger.exception("Error fetching resources: %s", e)
        return jsonify([]), 500

@app.route("/resources/<resource_id>", methods=["GET"])
def get_resource(resource_id):
    init_firestore()
    #  # --- ADD THIS CHECK ---
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    # # ----------------------
    try:
        doc = db.collection("articles").document(resource_id).get()
        if doc.exists:
            return jsonify({**doc.to_dict(), "id": doc.id})
        return jsonify({"error": "Resource not found"}), 404
    except Exception as e:
        logger.exception("Error retrieving resource %s: %s", resource_id, e)
        return jsonify({"error": "Internal server error"}), 500

@app.route("/resources", methods=["POST"])
def create_resource():
    init_firestore()
        # # --- ADD THIS CHECK ---
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    # # ----------------------

    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Missing/invalid JSON body"}), 400
    try:
        new_ref = db.collection("articles").document()
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
        doc_ref = db.collection("articles").document(resource_id)
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
      # --- ADD THIS CHECK ---
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    # ----------------------
        
    try:
        doc_ref = db.collection("articles").document(resource_id)
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
          # --- ADD THIS CHECK ---
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    # ----------------------

    data = request.get_json(silent=True) or {}
    user_id = data.get("userId")
    entry = data.get("entry")
    if not user_id or entry is None:
        return jsonify({"status": "error", "message": "userId and entry are required"}), 400

    # FRIEND SUGGESTION APPLIED: coerce string entries to dict
    if not isinstance(entry, dict):
        entry = {"text": entry}

    try:
        entry_payload = entry.copy() if isinstance(entry, dict) else {"text": str(entry)}
        entry_payload["dateAdded"] = FIRESTORE.SERVER_TIMESTAMP
        db.collection("users").document(user_id).collection("entries").add(entry_payload)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logger.exception("Error syncing journal: %s", e)
        return jsonify({"status": "error", "message": "Could not save entry"}), 500

# In backend/app.py 
@app.route("/users/<user_id>/journey", methods=["POST"])
def add_journey_item(user_id):
    """Adds a new action item to a user's journey. Returns the created document id."""
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    data = request.get_json(silent=True)
    if not data:
        raw = request.get_data(as_text=True)
        logger.warning("add_journey_item: Missing/invalid JSON body. Raw body: %s", raw)
        return jsonify({"status": "error", "message": "Missing/invalid JSON body"}), 400

    # Accept common client variations
    title = data.get("title") or data.get("name")
    resource_id = data.get("resource_id") or data.get("resourceId") or data.get("resource")
    client_id = data.get("clientId") or data.get("client_id")  # optional idempotency key

    if not title or not resource_id:
        logger.warning("add_journey_item: Missing required fields. Received JSON: %s", data)
        return jsonify({
            "status": "error",
            "message": "Missing required fields. Required: 'title' and 'resource_id' (or 'resourceId')."
        }), 400

    try:
        journey_item = {
            "title": title,
            "description": data.get("description", ""),
            "resourceId": resource_id,
            "isCompleted": bool(data.get("isCompleted", False)),
            "dateAdded": FIRESTORE.SERVER_TIMESTAMP
        }

        coll_ref = db.collection("users").document(user_id).collection("journey")

        if client_id:
            doc_ref = coll_ref.document(client_id)
            if doc_ref.get().exists:
                logger.info("add_journey_item: item with clientId %s already exists", client_id)
                return jsonify({"status": "exists", "id": doc_ref.id}), 200
            doc_ref.set(journey_item)
            return jsonify({"status": "success", "id": doc_ref.id}), 201

        # No client_id: use add() but handle different return shapes
        add_result = coll_ref.add(journey_item)
        doc_ref = None

        if hasattr(add_result, "id"):
            doc_ref = add_result
        elif isinstance(add_result, (list, tuple)):
            for part in add_result:
                if hasattr(part, "id"):
                    doc_ref = part
                    break

        if doc_ref is None:
            logger.exception("add_journey_item: Could not determine DocumentReference from add() result: %s", add_result)
            return jsonify({"status": "error", "message": "Created item but could not determine its id."}), 500

        return jsonify({"status": "success", "id": doc_ref.id}), 201

    except Exception as e:
        logger.exception(f"Error adding journey item for user {user_id}: {e}")
        return jsonify({"status": "error", "message": "Could not add item"}), 500

@app.route("/users/<user_id>/journey", methods=["GET"])
def get_journey_items(user_id):
    """Retrieves all action items for a user's journey."""
    init_firestore()
    # Secure the endpoint
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    try:                
        journey_ref = db.collection("users").document(user_id).collection("journey").order_by("dateAdded", direction=firestore_module.Query.DESCENDING)
        docs = journey_ref.stream()
        items = [{**doc.to_dict(), "id": doc.id} for doc in docs]
        return jsonify(items)
    except Exception as e:
        logger.exception(f"Error fetching journey for user {user_id}: {e}")
        return jsonify([]), 500

@app.route("/users/<user_id>/journey/<item_id>", methods=["PUT"])
def update_journey_item(user_id, item_id):
    init_firestore()

    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code
    data = request.get_json(silent=True) or {}
    try:
        doc_ref = db.collection("users").document(user_id).collection("journey").document(item_id)
        if not doc_ref.get().exists:
            return jsonify({"error": "Journey item not found"}), 404
        doc_ref.update(data)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logger.exception("Error updating journey item: %s", e)
        return jsonify({"error": "Could not update item"}), 500 

@app.route("/users/<user_id>/entries", methods=["GET"])
def get_journal_entries(user_id):
    """Return all journal entries for a user (most-recent first)."""
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    try:
        entries_ref = db.collection("users").document(user_id).collection("entries").order_by("dateAdded", direction=FIRESTORE.Query.DESCENDING)
        docs = entries_ref.stream()
        entries = [{**doc.to_dict(), "id": doc.id} for doc in docs]
        return jsonify(entries), 200
    except Exception as e:
        logger.exception("Error fetching journal entries for %s: %s", user_id, e)
        return jsonify([]), 500 

@app.route("/users/<user_id>/entries/<entry_id>", methods=["PUT"])
def update_journal_entry(user_id, entry_id):
    init_firestore()
    ok, info = require_api_key_and_quota(request)
    if not ok:
        msg, code = info
        return jsonify({"error": msg}), code

    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Missing/invalid JSON body"}), 400

    try:
        doc_ref = db.collection("users").document(user_id).collection("entries").document(entry_id)
        doc = doc_ref.get()
        if not doc.exists:
            return jsonify({"error": "Entry not found"}), 404 

        # Only accept expected editable fields
        update_payload = {}
        for field in ("title", "body", "text"):
            if field in data:
                update_payload[field] = data[field]

        # Optionally accept a client-provided date string, but don't trust it.
        if "date" in data:
            update_payload["date"] = data["date"]

        # Add server-side last modification marker
        update_payload["lastModified"] = FIRESTORE.SERVER_TIMESTAMP 

        if not update_payload:
            return jsonify({"status": "error", "message": "No editable fields provided."}), 400 

        doc_ref.update(update_payload)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logger.exception("Error updating journal entry %s for user %s: %s", entry_id, user_id, e)
        return jsonify({"status": "error", "message": "Could not update entry"}), 500  

@app.route("/_debug_fire")
def debug_fire():
    try:
        init_firestore()
        import google.cloud.firestore
        return jsonify({
            "firestore_ok": bool(db),
            "firestore_version": getattr(google.cloud.firestore, "__version__", "unknown"),
            "api_keys_collection_path": str(db.collection("api_keys")) if db else None
        })
    except Exception as e:
        import traceback
        print("🔥 Error in /_debug_fire:", traceback.format_exc())
        return jsonify({"error": "Internal server error", "details": str(e)}), 500 

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
