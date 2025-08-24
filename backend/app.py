import os
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

def create_app():
    """Creates and configures a Flask application instance."""
    app = Flask(__name__)
    app.config['SAHARA_CONTEXT'] = {}

    # --- Aastha Persona Prompt ---
    AASTHA_PERSONA_PROMPT = """You are Aastha, a compassionate and warm mental wellness companion. Your goal is to make the user feel heard, validated, and safe. You must follow this three-step loop in your response:
1. Reflect what the user is feeling in a gentle, understanding way.
2. Validate their feeling, assuring them it's an understandable or normal reaction.
3. Ask a simple, open-ended question to encourage them to explore their feeling further.
Never give direct advice, medical opinions, or say "I am an AI." Keep your responses concise and warm."""

    # --- Hugging Face Client Initialization ---
    def get_hf_client():
        if 'hf_client' in app.config['SAHARA_CONTEXT']:
            return app.config['SAHARA_CONTEXT']['hf_client']
        print("Fetching HF Token and initializing client...")
        try:
            secret_client = secretmanager.SecretManagerServiceClient()
            name = "projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
            response = secret_client.access_secret_version(name=name)
            token = response.payload.data.decode("UTF-8")
            hf_client = InferenceClient(token=token)
            app.config['SAHARA_CONTEXT']['hf_client'] = hf_client
            print("✅ Hugging Face client initialized.")
            return hf_client
        except Exception as e:
            print(f"FATAL: Could not initialize HF Client. Error: {e}")
            return None

    # --- Chat Endpoint ---
    @app.route("/chat", methods=["POST"])
    def handle_chat():
        client = get_hf_client()
        db = firestore.Client(project="sahara-wellness-prototype")

        if not client:
            return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

        user_message = request.json.get("message", "")
        prompt = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"

        try:
            response_text = ""
            for token in client.text_generation(prompt, model="HuggingFaceH4/zephyr-7b-beta", max_new_tokens=250, stream=True):
                response_text += token
            return jsonify({"reply": response_text})
        except Exception as e:
            print(f"Error calling HF API: {e}")
            return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

    # --- Journal Sync Endpoint ---
    @app.route("/journal/sync", methods=["POST"])
    def handle_journal_sync():
        db = firestore.Client(project="sahara-wellness-prototype")
        data = request.json
        user_id = data.get('userId')
        entry = data.get('entry')
        if not user_id or not entry:
            return jsonify({"status": "error", "message": "Missing userId or entry data"}), 400
        user_entries_ref = db.collection('users').document(user_id).collection('entries')
        user_entries_ref.add(entry)
        return jsonify({"status": "success", "message": "Journal entry synced successfully."}), 200

    # --- Resources Endpoint ---
    @app.route("/resources", methods=["GET"])
    def get_resources():
        db = firestore.Client(project="sahara-wellness-prototype")
        articles_ref = db.collection('articles')
        articles = [doc.to_dict() for doc in articles_ref.stream()]
        return jsonify(articles)

    return app

# --- Entry Point ---
app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)
