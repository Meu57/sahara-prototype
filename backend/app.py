# backend/app.py (FINAL VERSION with robust logging and initialization)

import os
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

app = Flask(__name__)

# --- Global variables for clients and status ---
db = None
hf_inference_client = None
AI_CORE_INITIALIZED = False
STARTUP_ERROR = None

# --- TOP-LEVEL INITIALIZATION BLOCK with loud, explicit logging ---
# This block runs only once when a new server instance starts.
try:
    print("LOG: ------ STARTING SAHARA BACKEND INITIALIZATION ------")

    # 1. Initialize Firestore Client
    print("LOG: Step 1/4 - Initializing Firestore client...")
    db = firestore.Client(project="sahara-wellness-prototype")
    print("✅ LOG: Step 1/4 - Firestore client initialized successfully.")

    # 2. Initialize Secret Manager Client
    print("LOG: Step 2/4 - Initializing Secret Manager client...")
    secret_client = secretmanager.SecretManagerServiceClient()
    print("✅ LOG: Step 2/4 - Secret Manager client initialized successfully.")

    # 3. Fetch the HF Token from Secret Manager
    print("LOG: Step 3/4 - Fetching Hugging Face token secret...")
    name = f"projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
    response = secret_client.access_secret_version(name=name)
    HF_TOKEN = response.payload.data.decode("UTF-8")
    
    # Add a check to make sure the token looks like a real token
    if not HF_TOKEN or not HF_TOKEN.startswith("hf_"):
        raise ValueError("Fetched token is invalid, empty, or does not start with 'hf_'.")
    print("✅ LOG: Step 3/4 - Hugging Face token fetched and validated successfully.")

    # 4. Initialize the Hugging Face Inference Client
    print("LOG: Step 4/4 - Initializing Hugging Face InferenceClient...")
    hf_inference_client = InferenceClient(token=HF_TOKEN)
    
    AI_CORE_INITIALIZED = True
    print("✅✅✅ LOG: AI CORE IS FULLY INITIALIZED AND READY! ✅✅✅")

except Exception as e:
    # If ANY of the steps above fail, this will be printed loudly in the logs.
    print("❌❌❌ FATAL STARTUP ERROR - AI CORE FAILED TO INITIALIZE ❌❌❌")
    print(f"The specific error was: {e}")
    # We store the error to report it in our API endpoints
    STARTUP_ERROR = str(e)


# --- Aastha Persona Prompt ---
AASTHA_PERSONA_PROMPT = """You are Aastha, a compassionate and warm mental wellness companion. Your goal is to make the user feel heard, validated, and safe. You must follow this three-step loop in your response:
1. Reflect what the user is feeling in a gentle, understanding way.
2. Validate their feeling, assuring them it's an understandable or normal reaction.
3. Ask a simple, open-ended question to encourage them to explore their feeling further.
Never give direct advice, medical opinions, or say "I am an AI." Keep your responses concise and warm."""

# --- Chat Endpoint ---
@app.route("/chat", methods=["POST"])
def handle_chat():
    # This check now explicitly uses our boolean flag for clarity.
    if not AI_CORE_INITIALIZED:
        print(f"ERROR: Replying with startup error. Details: {STARTUP_ERROR}")
        # Return the specific startup error to the app for easier debugging
        return jsonify({"reply": f"Sorry, a critical server error occurred: {STARTUP_ERROR}"}), 503

    user_message = request.json.get("message", "")
    print(f"Received LIVE chat message: {user_message}")

    prompt = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"

    try:
        response_text = ""
        for token in hf_inference_client.text_generation(prompt, model="HuggingFaceH4/zephyr-7b-beta", max_new_tokens=250, stream=True):
            response_text += token
        print(f"Generated AI response: {response_text}")
        return jsonify({"reply": response_text})
    except Exception as e:
        print(f"Error calling Hugging Face API: {e}")
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."})

# --- Journal Sync Endpoint ---
@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    if not AI_CORE_INITIALIZED:
        return jsonify({"status": "error", "message": f"Server not ready: {STARTUP_ERROR}"}), 503

    data = request.json
    # ... rest of your journal logic is the same

# --- Resources Endpoint ---
@app.route("/resources", methods=["GET"])
def get_resources():
    if not AI_CORE_INITIALIZED:
        return jsonify([]), 503 # Return empty list on error

    print("Fetching resources from Firestore...")
    # ... rest of your resources logic is the same

# --- Entry Point ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)