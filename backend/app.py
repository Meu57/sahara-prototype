# backend/app.py (UPGRADED for Live AI using Hugging Face API)

import os
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

# --- Initialize App and Global Clients ---
app = Flask(__name__)
db = firestore.Client(project="sahara-wellness-prototype")
hf_inference_client = None # Will be initialized on startup

# --- Function to fetch the Hugging Face Token securely ---
def get_hf_token():
    """Fetches the Hugging Face token from Google Cloud Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        # This is the full resource name of your secret's latest version.
        name = "projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
        response = client.access_secret_version(name=name)
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"FATAL: Could not access Secret Manager. Is the API enabled? Does the service account have permissions? Error: {e}")
        # Return None so the app knows the client is not configured.
        return None

# --- Initialize the Hugging Face Client ONCE on startup ---
print("Initializing Hugging Face client...")
HF_TOKEN = get_hf_token()
if HF_TOKEN:
    hf_inference_client = InferenceClient(token=HF_TOKEN)
    print("✅ Hugging Face client initialized successfully.")
else:
    print("❌ WARNING: Hugging Face token not found. The /chat endpoint will not work.")


# --- Official Aastha Persona Prompt for Zephyr ---
AASTHA_PERSONA_PROMPT = """You are Aastha, a compassionate and warm mental wellness companion from India who speaks in a gentle and reassuring tone.
Your goal is to make the user feel heard, validated, and safe.
You MUST follow this three-step loop in your response:
1.  Reflect what the user is feeling in an understanding way.
2.  Validate their feeling, assuring them it's a normal and understandable reaction.
3.  Ask a simple, open-ended question to encourage them to explore their feeling further.
NEVER give direct advice, medical opinions, or break character. Keep your responses concise and warm."""

# --- API ENDPOINTS ---

@app.route("/chat", methods=["POST"])
def handle_chat():
    """Handles incoming chat messages and returns a LIVE AI response from our champion model."""
    if not hf_inference_client:
        return jsonify({"error": "AI service is not configured correctly. Check server logs."}), 503

    user_message = request.json.get("message", "")
    print(f"Received LIVE chat message: {user_message}") 

    # We use the specific chat template for the Zephyr model.
    prompt_template = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"
    
    try:
        # Call the Hugging Face Inference API for our champion model
        response_stream = hf_inference_client.text_generation(
            prompt_template, 
            model="HuggingFaceH4/zephyr-7b-beta",
            max_new_tokens=250, 
            temperature=0.7, 
            top_p=0.95,
            stream=True # Use streaming for a better feel later
        )
        
        # Combine the streamed tokens into a single response
        response_text = "".join(token for token in response_stream)
        
        print(f"Generated AI response: {response_text}")
        return jsonify({"reply": response_text})

    except Exception as e:
        print(f"Error calling Hugging Face API: {e}")
        # Provide a safe, generic response if the AI service fails
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})


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
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)