# backend/app.py (FINALIZED FOR GEMINI 1.5 PRO IN ASIA-SOUTH1)

import os
import datetime
from flask import Flask, request, jsonify
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel, Part

# --- Configuration ---
PROJECT_ID = "sahara-wellness-prototype"
LOCATION = "asia-south1"  # ✅ Region locked by infrastructure
GEMINI_MODEL_NAME = "gemini-1.5-pro"  # ✅ Valid model in asia-south1
DAILY_GLOBAL_API_LIMIT = 240  # Safe buffer under 250 RPD free tier

# --- Initialization ---
app = Flask(__name__)
db = firestore.Client(project=PROJECT_ID)
vertexai.init(project=PROJECT_ID, location=LOCATION)

# --- Fair Use Governor ---
def check_and_update_global_quota():
    today_str = datetime.date.today().isoformat()
    counter_ref = db.collection('usage_stats').document(today_str)
    counter_doc = counter_ref.get()

    if counter_doc.exists:
        current_count = counter_doc.to_dict().get('api_calls', 0)
        if current_count >= DAILY_GLOBAL_API_LIMIT:
            print(f"Daily global limit of {DAILY_GLOBAL_API_LIMIT} reached. Blocking request.")
            return False

    counter_ref.set({'api_calls': firestore.Increment(1)}, merge=True)
    return True

# --- Chat Endpoint ---
@app.route("/chat", methods=["POST"])
def handle_chat():
    if not check_and_update_global_quota():
        return jsonify({"reply": "Aastha has been very busy... Please check back tomorrow."}), 503

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
        model = GenerativeModel(GEMINI_MODEL_NAME)
        response = model.generate_content([full_prompt])
        ai_reply = response.text

        print(f"Gemini responded: {ai_reply}")
        return jsonify({"reply": ai_reply})
    except Exception as e:
        print(f"Error calling Vertex AI: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now..."}), 500

# --- Local Testing ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
