# backend/app.py (Definitive V2 with Friends' Feedback)

import os
import datetime
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

# --- Governor (remains the same) ---
def check_and_update_global_quota():
    if not db: return False
    today_str = datetime.date.today().isoformat()
    counter_ref = db.collection('usage_stats').document(today_str)
    counter_doc = counter_ref.get()
    if counter_doc.exists and counter_doc.to_dict().get('api_calls', 0) >= DAILY_GLOBAL_API_LIMIT:
        return False
    counter_ref.set({'api_calls': firestore.Increment(1)}, merge=True)
    return True
    
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
    if not user_id:
        user_id = str(uuid.uuid4())
        created_new_user = True
        print(f"No userId from client; generated new id: {user_id}")

    try:
        user_ref = db.collection("users").document(user_id)
        user_ref.set({"last_active": firestore.SERVER_TIMESTAMP}, merge=True)
    except Exception as e:
        print(f"Warning: Failed to write user doc for {user_id}. Reason: {e}")

    # The new, enhanced system prompt
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
    
    full_prompt = f"{system_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        # Check quota *before* the expensive AI call
        if not check_and_update_global_quota():
            return jsonify({"reply": "Aastha is resting. Please check back tomorrow."}), 503

        response = model.generate_content([full_prompt])
        ai_reply = response.text
        
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