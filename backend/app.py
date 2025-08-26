# backend/app.py (Definitive Final Version)

import os
import datetime
from flask import Flask, request, jsonify
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel

# --- Configuration ---
PROJECT_ID = "sahara-wellness-prototype"
LOCATION = "asia-south1"
GEMINI_MODEL_NAME = "gemini-1.5-pro"

DAILY_GLOBAL_API_LIMIT = 240  # Safe buffer

# --- Initialization ---
app = Flask(__name__)
try:
    db = firestore.Client(project=PROJECT_ID)
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    model = GenerativeModel(GEMINI_MODEL_NAME)
    print("✅ Firestore and Vertex AI clients initialized successfully.")
except Exception as e:
    print(f"❌ CRITICAL ERROR during initialization: {e}")
    model = None
    db = None

# --- Helper Function: Fair Use Governor ---
def check_and_update_global_quota():
    if not db:
        return False
    today_str = datetime.date.today().isoformat()
    counter_ref = db.collection('usage_stats').document(today_str)
    counter_doc = counter_ref.get()
    if counter_doc.exists and counter_doc.to_dict().get('api_calls', 0) >= DAILY_GLOBAL_API_LIMIT:
        print("Daily global limit reached. Blocking request.")
        return False
    counter_ref.set({'api_calls': firestore.Increment(1)}, merge=True)
    return True

# --- API ENDPOINTS ---

@app.route("/")
def index():
    return "Sahara Backend is healthy.", 200

@app.route("/chat", methods=["POST"])
def handle_chat():
    if not model:
        return jsonify({"reply": "AI Service is currently unavailable."}), 503
    if not check_and_update_global_quota():
        return jsonify({"reply": "Aastha is resting. Please check back tomorrow."}), 503

    user_message = request.json.get("message", "")
    print(f"Received LIVE chat message: {user_message}")

    system_prompt = (
        "You are Aastha, a compassionate, warm, and empathetic mental health companion. "
        "Your approach always follows a three-step 'reflect-validate-question' loop. "
        "1. Reflect what the user is feeling in your own words. "
        "2. Validate their feelings as normal and understandable. "
        "3. Ask a gentle, open-ended question to encourage them to explore further. "
        "Never give medical advice. Keep your responses concise and supportive."
    )
    full_prompt = f"{system_prompt}\n\nUser: {user_message}\nAastha:"

    try:
        response = model.generate_content([full_prompt])
        ai_reply = response.text
        print(f"Gemini responded: {ai_reply}")
        return jsonify({"reply": ai_reply})
    except Exception as e:
        print(f"Error calling Vertex AI: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now."}), 500

@app.route("/resources", methods=["GET"])
def get_resources():
    if not db:
        return jsonify({"error": "Database service not available."}), 503
    try:
        articles_ref = db.collection('articles')
        articles = [doc.to_dict() for doc in articles_ref.stream()]
        return jsonify(articles)
    except Exception as e:
        print(f"Error fetching from Firestore: {e}")
        return jsonify({"error": "Could not fetch resources."}), 500

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    if not db:
        return jsonify({"error": "Database service not available."}), 503

    data = request.json
    user_id = data.get('userId')
    entry = data.get('entry')
    if not user_id or not entry:
        return jsonify({"status": "error", "message": "Missing data"}), 400

    try:
        user_entries_ref = db.collection('users').document(user_id).collection('entries')
        user_entries_ref.add(entry)
        return jsonify({"status": "success"}), 200
    except Exception as e:
        print(f"Error saving to Firestore: {e}")
        return jsonify({"error": "Could not save journal entry."}), 500

# --- Local Testing ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
