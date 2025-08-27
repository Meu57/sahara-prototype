# backend/app.py (Final Version with Memory Summarization and Conversation Count)

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
DAILY_GLOBAL_API_LIMIT = 240

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

# --- Governor ---
def check_and_update_global_quota():
    if not db: return False
    today_str = datetime.date.today().isoformat()
    counter_ref = db.collection('usage_stats').document(today_str)
    counter_doc = counter_ref.get()
    if counter_doc.exists and counter_doc.to_dict().get('api_calls', 0) >= DAILY_GLOBAL_API_LIMIT:
        return False
    counter_ref.set({'api_calls': firestore.Increment(1)}, merge=True)
    return True

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
def index(): return "Sahara Backend is healthy.", 200

@app.route("/chat", methods=["POST"])
def handle_chat():
    if not model: return jsonify({"reply": "AI Service not available."}), 503

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




    full_prompt = f"{system_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        if not check_and_update_global_quota():
            return jsonify({"reply": "Aastha is resting. Please check back tomorrow."}), 503

        response = model.generate_content([full_prompt])
        ai_reply = response.text

        # --- Background memory update ---
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
    if not db: return jsonify([]), 503
    try:
        articles_ref = db.collection('articles')
        articles = [doc.to_dict() for doc in articles_ref.stream()]
        return jsonify(articles)
    except Exception as e: return jsonify([]), 500

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    if not db: return jsonify({"status": "error"}), 503
    data = request.json or {}
    user_id = data.get('userId')
    entry = data.get('entry')
    if not user_id or not entry: return jsonify({"status": "error"}), 400
    try:
        user_entries_ref = db.collection('users').document(user_id).collection('entries')
        user_entries_ref.add(entry)
        return jsonify({"status": "success"}), 200
    except Exception as e: return jsonify({"status": "error"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
