# backend/app.py (Final Version with Per-Key Security and Robust Transactions)
import os
import datetime
import threading
import uuid
from flask import Flask, request, jsonify
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel

# --- Configuration ---
PROJECT_ID = "sahara-wellness-prototype" 
LOCATION = "asia-south1"
MODEL_NAME = "gemini-1.5-pro"

# --- Initialization ---
app = Flask(__name__)

try:
    db = firestore.Client(project=PROJECT_ID)
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    model = GenerativeModel(MODEL_NAME)
    print("✅ Firestore and Vertex AI clients initialized successfully.")
except Exception as e:
    print(f"❌ CRITICAL ERROR during initialization: {e}")
    model = None
    db = None

# NOTE: The global 'transaction' variable has been correctly removed.

# --- NEW SECURITY MIDDLEWARE ---
def require_api_key_and_quota(request):
    """
    Checks for a valid API key and ensures its usage quota has not been exceeded.
    Uses a Firestore transaction for safe, concurrent updates.
    """
    if not db:
        return False, ("Server is not properly initialized.", 503)

    api_key = request.headers.get("x-api-key")
    if not api_key:
        return False, ("API key is missing.", 401)

    key_ref = db.collection('api_keys').document(api_key)
    today_str = datetime.date.today().isoformat()

    try:
        @firestore.transactional
        def update_usage_in_transaction(transaction, key_ref, today_str):
            key_snapshot = key_ref.get(transaction=transaction)

            if not key_snapshot.exists:
                return False, ("Invalid API key.", 403)

            key_data = key_snapshot.to_dict()
            daily_limit = key_data.get("daily_limit", 50) 
            usage = key_data.get("usage", 0)
            last_used = key_data.get("last_used", "")

            # If last used was before today, reset the counter
            if last_used < today_str:
                usage = 0

            if usage >= daily_limit:
                return False, ("API quota for this key has been exceeded for today.", 429)

            # Increment usage and update the last_used date
            transaction.update(key_ref, {
                'usage': usage + 1,
                'last_used': today_str
            })
            return True, None

        # --- THE FIX IS APPLIED HERE ---
        # This gets the transaction object and runs the function all in one safe step.
        is_ok, info_or_error = db.run_transaction(update_usage_in_transaction, key_ref, today_str)
        return is_ok, info_or_error

    except Exception as e:
        print(f"Error during Firestore transaction: {e}")
        return False, ("Internal server error during quota check.", 500)

# --- Memory Summarization Helper ---
def update_memory_summary_in_background(user_id, prev_memory, user_message, ai_reply):
    print(f"Starting background memory update for user: {user_id}")
    try:
        summarization_prompt = (
            "You are a concise memory summarizer. From the PREVIOUS MEMORY and the LATEST EXCHANGE, "
            "produce a ONE-SENTENCE summary (15-25 words) capturing the key themes, user's emotional state, "
            "or important facts the companion should remember. Output only the sentence.\n\n"
            f"PREVIOUS MEMORY: {prev_memory}\n"
            f"LATEST EXCHANGE:\nUser: {user_message}\nAastha: {ai_reply}\n\n"
            "UPDATED ONE-SENTENCE SUMMARY:"
        )
        response = model.generate_content([summarization_prompt])
        new_summary = response.text.strip().replace("\n", " ")
        user_ref = db.collection("users").document(user_id)
        user_ref.set({
            "memory_summary": new_summary,
            "last_memory_update": firestore.SERVER_TIMESTAMP
        }, merge=True)
        print(f"Successfully completed background memory update for user: {user_id}")
        print(f"New summary: {new_summary}")
    except Exception as e:
        print(f"CRITICAL ERROR in background memory update for {user_id}: {e}")

# --- Endpoints ---
@app.route("/")
def index():
    return "Sahara Backend is healthy.", 200

@app.route("/chat", methods=["POST"])
def handle_chat():
    is_ok, info_or_error = require_api_key_and_quota(request)
    if not is_ok:
        error_message, status_code = info_or_error
        return jsonify({"error": error_message}), status_code

    if not model:
        return jsonify({"reply": "AI Service not available."}), 503

    data = request.json or {}
    user_message = data.get("message", "")
    user_id = data.get("userId")
    created_new_user = False
    memory_summary = ""

    if not user_id:
        user_id = str(uuid.uuid4())
        created_new_user = True
        print(f"No userId from client; generated new id: {user_id}")

    try:
        user_ref = db.collection("users").document(user_id)
        user_doc = user_ref.get()

        if not user_doc.exists:
            print(f"First message from new user. Creating document for: {user_id}")
            user_ref.set({
                "created_at": firestore.SERVER_TIMESTAMP,
                "memory_summary": "",
                "conversation_count": 1
            })
            memory_summary = ""
        else:
            user_ref.set({
                "last_active": firestore.SERVER_TIMESTAMP,
                "conversation_count": firestore.Increment(1)
            }, merge=True)
            memory_summary = user_doc.to_dict().get("memory_summary", "")
    except Exception as e:
        print(f"Warning: Failed to access or update user doc for {user_id}. Reason: {e}")

    system_prompt = (
        "You are Aastha, a compassionate and warm AI companion. Your approach follows a 'reflect-validate-question' loop.\n"
        "VARIATION RULES:\n"
        "- Do not always start with 'It sounds like'. Use varied phrases like 'That must feel...', 'I can hear that...', or 'I'm noticing that...'.\n"
        "- Keep responses to 2-3 concise sentences: one for reflection, one for validation, and one gentle, open question.\n"
        "- Be warm and human. Use phrases like 'I’m here with you' or 'that’s a heavy thing to carry'.\n"
        "FEW-SHOT EXAMPLES:\n"
        "User: I just feel so lost.\n"
        "Aastha: It can feel so directionless to be lost. That's a completely normal part of figuring things out. What does 'lost' feel like for you today?\n"
        "User: I'm just so tired of everything.\n"
        "Aastha: I can hear the exhaustion in your words. Feeling tired of it all is a heavy weight to carry. What's one thing that is draining your energy the most?"
    )

    context_prompt = (
    f"REMEMBER THIS from past conversations: {memory_summary if memory_summary else 'This is the user\'s first conversation.'}"
        )



    full_prompt = f"{system_prompt}\n\n{context_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        response = model.generate_content([full_prompt])
        ai_reply = response.text

        memory_thread = threading.Thread(
            target=update_memory_summary_in_background,
            args=(user_id, memory_summary, user_message, ai_reply)
        )
        memory_thread.start()

        response_payload = {"reply": ai_reply}
        if created_new_user:
            response_payload["userId"] = user_id
        return jsonify(response_payload)
        
    except Exception as e:
        print(f"Error calling Vertex AI: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now."}), 500

@app.route("/resources", methods=["GET"])
def get_resources():
    is_ok, info_or_error = require_api_key_and_quota(request)
    if not is_ok:
        error_message, status_code = info_or_error
        return jsonify({"error": error_message}), status_code

    if not db:
        return jsonify([]), 503
        
    try:
        articles_ref = db.collection('articles')
        articles = [doc.to_dict() for doc in articles_ref.stream()]
        return jsonify(articles)
    except Exception as e:
        print(f"Error fetching resources: {e}")
        return jsonify([]), 500

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    is_ok, info_or_error = require_api_key_and_quota(request)
    if not is_ok:
        error_message, status_code = info_or_error
        return jsonify({"error": error_message}), status_code

    if not db:
        return jsonify({"status": "error", "message": "Database not connected"}), 503

    data = request.json or {}
    user_id = data.get('userId')
    entry = data.get('entry')

    if not user_id or not entry:
        return jsonify({"status": "error", "message": "userId and entry are required"}), 400
    
    try:
        user_entries_ref = db.collection('users').document(user_id).collection('entries')
        user_entries_ref.add(entry)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        print(f"Error syncing journal: {e}")
        return jsonify({"status": "error", "message": "Could not save entry"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=False)