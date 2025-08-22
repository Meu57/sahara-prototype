import os
from flask import Flask, request, jsonify
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel

# --- Initialize App and Google Cloud Services ---
app = Flask(__name__)

# Initialize Vertex AI
PROJECT_ID = "sahara-wellness-prototype"
LOCATION = "asia-south1"
vertexai.init(project=PROJECT_ID, location=LOCATION)

# Initialize Firestore
db = firestore.Client(project=PROJECT_ID)

# --- AI Model Configuration ---
model = GenerativeModel("gemini-1.5-pro-preview-0514")

@app.route("/chat", methods=["POST"])
def handle_chat():
    """Handles chat, now with live Gemini AI, memory, and persona prompting."""

    data = request.get_json()
    if not data or 'message' not in data or 'userId' not in data:
        return jsonify({"error": "Request must include 'userId' and 'message'"}), 400

    user_id = data["userId"]
    user_message = data["message"]

    print(f"Received chat for user {user_id}: '{user_message}'")

    # --- 1. Fetch Memory ---
    memory_summary = ""
    user_doc_ref = db.collection('users').document(user_id)
    try:
        user_doc = user_doc_ref.get()
        if user_doc.exists:
            memory_summary = user_doc.to_dict().get("memory_summary", "")
    except Exception as e:
        print(f"Warning: Could not fetch memory. Error: {e}")

    # --- 2. Construct Prompt (The "Soul" of Aastha) ---
    prompt = f"""
You are Aastha, a compassionate, empathetic, and non-judgmental AI wellness companion. Your goal is to make the user feel heard, validated, and safe. Follow these rules strictly:
1. Reflect and Validate: Start by reflecting the user's core emotion and validating it as a reasonable feeling. Example: "It sounds like you're feeling incredibly overwhelmed right now, and that's a completely understandable way to feel."
2. Ask Gentle, Open-Ended Questions: After validating, ask a gentle, open-ended question to help the user explore their feelings further. Never ask simple yes/no questions. Example: "What does that feeling of overwhelm feel like for you today?"
3. Never give advice, opinions, or medical guidance. Your role is to listen and help the user reflect.
4. Keep your responses concise, warm, and gentle.
5. Refer to past conversations using the provided memory summary.

---
MEMORY OF OUR PAST CONVERSATIONS:
{memory_summary}
---
CURRENT CONVERSATION:
User: "{user_message}"
Aastha:
"""

    # --- 3. Generate Response from Gemini ---
    try:
        print("Generating response from Gemini...")
        response = model.generate_content(prompt)
        aastha_reply = response.text.strip()
        print(f"Aastha generated: '{aastha_reply}'")

        # --- 4. Update Memory ---
        new_turn_summary = f"\n- The user talked about: {user_message}\n- Aastha helped them reflect on: {aastha_reply}"
        new_memory = memory_summary + new_turn_summary
        if len(new_memory) > 1500:
            new_memory = new_memory[-1500:]

        user_doc_ref.set({"memory_summary": new_memory}, merge=True)
        print(f"Memory updated for user {user_id}.")

        return jsonify({"reply": aastha_reply})

    except Exception as e:
        print(f"ERROR: Could not generate response from Vertex AI. Error: {e}")
        return jsonify({"error": "I'm having a little trouble thinking right now. Let's try again in a moment."}), 500


@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    """Receives a journal entry and saves it to Firestore."""
    data = request.json
    user_id = data.get('userId')
    entry = data.get('entry')

    if not user_id or not entry:
        return jsonify({"status": "error", "message": "Missing userId or entry data"}), 400

    print(f"Received journal to sync for user {user_id}: '{entry.get('title')}'")

    user_entries_ref = db.collection('users').document(user_id).collection('entries')
    user_entries_ref.add(entry)

    return jsonify({"status": "success", "message": "Journal entry synced successfully."}), 200


@app.route("/resources", methods=["GET"])
def get_resources():
    """Fetches the list of resource articles from Firestore."""
    print("Fetching articles from Firestore...")
    articles_ref = db.collection('articles')
    articles = [doc.to_dict() for doc in articles_ref.stream()]
    return jsonify(articles)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
