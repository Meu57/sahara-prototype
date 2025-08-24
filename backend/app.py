import os
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

app = Flask(__name__)

# Initialize clients globally
db = None
hf_inference_client = None

# --- TOP-LEVEL INITIALIZATION BLOCK ---
try:
    print("LOG: Initializing Firestore client...")
    db = firestore.Client(project="sahara-wellness-prototype")
    print("✅ Firestore client ready.")

    print("LOG: Initializing Secret Manager client...")
    secret_client = secretmanager.SecretManagerServiceClient()
    print("✅ Secret Manager client ready.")

    print("LOG: Fetching Hugging Face token...")
    name = "projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
    response = secret_client.access_secret_version(name=name)
    HF_TOKEN = response.payload.data.decode("UTF-8")
    print("✅ HF token retrieved.")

    print("LOG: Initializing Hugging Face InferenceClient...")
    hf_inference_client = InferenceClient(token=HF_TOKEN)
    print("✅✅✅ AI CORE INITIALIZED ✅✅✅")

except Exception as e:
    print("❌❌❌ FATAL STARTUP ERROR ❌❌❌")
    print(f"Initialization failed: {e}")
    STARTUP_ERROR = str(e)
else:
    STARTUP_ERROR = None

# --- Aastha Persona Prompt ---
AASTHA_PERSONA_PROMPT = """You are Aastha, a compassionate and warm mental wellness companion. Your goal is to make the user feel heard, validated, and safe. You must follow this three-step loop in your response:
1. Reflect what the user is feeling in a gentle, understanding way.
2. Validate their feeling, assuring them it's an understandable or normal reaction.
3. Ask a simple, open-ended question to encourage them to explore their feeling further.
Never give direct advice, medical opinions, or say "I am an AI." Keep your responses concise and warm."""

# --- Chat Endpoint ---
@app.route("/chat", methods=["POST"])
def handle_chat():
    if STARTUP_ERROR:
        print(f"ERROR: Startup failed — {STARTUP_ERROR}")
        return jsonify({"reply": f"Server startup error: {STARTUP_ERROR}"}), 500

    if not hf_inference_client:
        return jsonify({"reply": "AI client is not available. Check startup logs."}), 503

    user_message = request.json.get("message", "")
    print(f"Received chat message: {user_message}")

    prompt = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"

    try:
        response_text = ""
        for token in hf_inference_client.text_generation(prompt, model="HuggingFaceH4/zephyr-7b-beta", max_new_tokens=250, stream=True):
            response_text += token
        print(f"Generated response: {response_text}")
        return jsonify({"reply": response_text})
    except Exception as e:
        print(f"HF API error: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

# --- Journal Sync Endpoint ---
@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    if STARTUP_ERROR:
        return jsonify({"status": "error", "message": f"Startup error: {STARTUP_ERROR}"}), 500

    data = request.json
    user_id = data.get('userId')
    entry = data.get('entry')

    if not user_id or not entry:
        return jsonify({"status": "error", "message": "Missing userId or entry data"}), 400

    print(f"Syncing journal for user {user_id}: {entry.get('title', 'Untitled')}")
    user_entries_ref = db.collection('users').document(user_id).collection('entries')
    user_entries_ref.add(entry)

    return jsonify({"status": "success", "message": "Journal entry synced successfully."}), 200

# --- Resources Endpoint ---
@app.route("/resources", methods=["GET"])
def get_resources():
    if STARTUP_ERROR:
        return jsonify({"status": "error", "message": f"Startup error: {STARTUP_ERROR}"}), 500

    print("Fetching resources from Firestore...")
    articles_ref = db.collection('articles')
    articles = [doc.to_dict() for doc in articles_ref.stream()]
    return jsonify(articles)

# --- Entry Point ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)
