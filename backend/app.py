# backend/app.py (FINAL, MORE ROBUST VERSION)
import os
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

app = Flask(__name__)
db = firestore.Client(project="sahara-wellness-prototype")

# --- We will now initialize the client LAZILY inside the request ---
hf_inference_client = None
HF_TOKEN = None

def get_hf_client_and_token():
    """Initializes the HF Client if it doesn't exist."""
    global hf_inference_client, HF_TOKEN
    
    # If we already have the token, don't fetch it again.
    if HF_TOKEN:
        return hf_inference_client
        
    print("Fetching HF Token from Secret Manager for the first time...")
    try:
        secret_client = secretmanager.SecretManagerServiceClient()
        name = f"projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
        response = secret_client.access_secret_version(name=name)
        HF_TOKEN = response.payload.data.decode("UTF-8")
        
        hf_inference_client = InferenceClient(token=HF_TOKEN)
        print("✅ Hugging Face client initialized successfully.")
        return hf_inference_client
    except Exception as e:
        print(f"FATAL: Could not access Secret or initialize HF Client. Error: {e}")
        return None

# (Keep your AASTHA_PERSONA_PROMPT here, unchanged)
AASTHA_PERSONA_PROMPT = """..."""

@app.route("/chat", methods=["POST"])
def handle_chat():
    """Handles chat messages with a robust, lazily-initialized client."""
    client = get_hf_client_and_token() # This will initialize on the first call
    
    if not client:
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

    user_message = request.json.get("message", "")
    print(f"Received LIVE chat message: {user_message}") 

    prompt_template = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"
    
    try:
        response_text = ""
        for token in client.text_generation(prompt_template, model="HuggingFaceH4/zephyr-7b-beta", max_new_tokens=250, stream=True):
            response_text += token
        
        print(f"Generated AI response: {response_text}")
        return jsonify({"reply": response_text})
    except Exception as e:
        print(f"Error calling Hugging Face API: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

# --- The other endpoints remain the same ---
# @app.route("/journal/sync", methods=["POST"]) ...
# @app.route("/resources", methods=["GET"]) ...
# if __name__ == "__main__": ...


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
    # This is only for local testing. On Cloud Run, Gunicorn will run the 'app' object.
    # The GCLOUD_PROJECT environment variable is set automatically in the Cloud Run environment.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True) ..