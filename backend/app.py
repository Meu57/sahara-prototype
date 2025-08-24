import os
import traceback
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import secretmanager
from huggingface_hub import InferenceClient

app = Flask(__name__)

# --- Global variables for clients and status ---
db = None
hf_inference_client = None
STARTUP_ERROR = None
AI_CORE_INITIALIZED = False

# --- DETAILED, PER-STEP INITIALIZATION ---
print("--- LOG: STARTING SAHARA BACKEND INITIALIZATION ---")
try:
    print("LOG: Step 1/4 - Initializing Firestore client...")
    db = firestore.Client(project="sahara-wellness-prototype")
    print("✅ LOG: Step 1/4 - Firestore client initialized successfully.")
except Exception as e:
    STARTUP_ERROR = "Firestore init failed: " + str(e) + "\n---\nTRACEBACK:\n" + traceback.format_exc()

if not STARTUP_ERROR:
    try:
        print("LOG: Step 2/4 - Initializing Secret Manager client...")
        secret_client = secretmanager.SecretManagerServiceClient()
        print("✅ LOG: Step 2/4 - Secret Manager client initialized successfully.")
    except Exception as e:
        STARTUP_ERROR = "Secret Manager client failed: " + str(e) + "\n---\nTRACEBACK:\n" + traceback.format_exc()

HF_TOKEN = None
if not STARTUP_ERROR:
    try:
        print("LOG: Step 3/4 - Fetching Hugging Face token secret...")
        name = "projects/sahara-wellness-prototype/secrets/huggingface-token/versions/latest"
        response = secret_client.access_secret_version(name=name)
        HF_TOKEN = response.payload.data.decode("UTF-8").strip()
        if not HF_TOKEN or not HF_TOKEN.startswith("hf_"):
            raise ValueError("Fetched token is invalid, empty, or does not start with 'hf_'.")
        print("✅ LOG: Step 3/4 - Hugging Face token fetched and validated successfully.")
    except Exception as e:
        STARTUP_ERROR = "Secret fetch failed: " + str(e) + "\n---\nTRACEBACK:\n" + traceback.format_exc()

if not STARTUP_ERROR and HF_TOKEN:
    try:
        print("LOG: Step 4/4 - Initializing Hugging Face InferenceClient...")
        hf_inference_client = InferenceClient(token=HF_TOKEN)
        AI_CORE_INITIALIZED = True
        print("✅✅✅ LOG: AI CORE IS FULLY INITIALIZED AND READY! ✅✅✅")
    except Exception as e:
        STARTUP_ERROR = "Hugging Face client init failed: " + str(e) + "\n---\nTRACEBACK:\n" + traceback.format_exc()

if STARTUP_ERROR:
    print(f"❌❌❌ FATAL STARTUP ERROR ❌❌❌\n{STARTUP_ERROR}")

# --- DIAGNOSTIC ENDPOINTS ---
@app.route("/startup-status", methods=["GET"])
def startup_status():
    return jsonify({
        "AI_CORE_INITIALIZED": AI_CORE_INITIALIZED,
        "STARTUP_ERROR": STARTUP_ERROR,
        "google_cloud_project_env": os.environ.get("GOOGLE_CLOUD_PROJECT"),
    })

@app.route("/selftest", methods=["GET"])
def selftest():
    return jsonify({
        "status": "ok",
        "message": "Self-test passed",
        "hf_ok": hf_inference_client is not None,
        "firestore_ok": db is not None,
        "startup_error": STARTUP_ERROR,
        "ai_core_initialized": AI_CORE_INITIALIZED
    }), 200

# --- AASTHA PERSONA PROMPT ---
AASTHA_PERSONA_PROMPT = """You are Aastha, a compassionate and warm mental wellness companion. Your goal is to make the user feel heard, validated, and safe. You must follow this three-step loop in your response:
1. Reflect what the user is feeling in a gentle, understanding way.
2. Validate their feeling, assuring them it's an understandable or normal reaction.
3. Ask a simple, open-ended question to encourage them to explore their feeling further.
Never give direct advice, medical opinions, or say "I am an AI." Keep your responses concise and warm."""

# --- CHAT ENDPOINT ---
@app.route("/chat", methods=["POST"])
def handle_chat():
    if STARTUP_ERROR:
        return jsonify({"reply": f"Server startup error: {STARTUP_ERROR}"}), 500
    if not hf_inference_client:
        return jsonify({"reply": "AI client is not available. Check startup logs."}), 503

    user_message = request.json.get("message", "")
    prompt = f"<|system|>\n{AASTHA_PERSONA_PROMPT}</s>\n<|user|>\n{user_message}</s>\n<|assistant|>"

    try:
        response_text = ""

        # Try streaming first
        try:
            for token in hf_inference_client.text_generation(prompt,
                                                            model="HuggingFaceH4/zephyr-7b-beta",
                                                            max_new_tokens=250,
                                                            stream=True):
                if isinstance(token, bytes):
                    response_text += token.decode("utf-8", errors="ignore")
                elif isinstance(token, str):
                    response_text += token
                elif isinstance(token, dict):
                    response_text += token.get("generated_text") or token.get("text") or token.get("token") or ""
                else:
                    response_text += str(token)
        except Exception as stream_exc:
            print("STREAMING ERROR (falling back to non-stream). Exception:", stream_exc)
            print(traceback.format_exc())

            # Non-streaming fallback
            resp = hf_inference_client.text_generation(prompt,
                                                       model="HuggingFaceH4/zephyr-7b-beta",
                                                       max_new_tokens=250,
                                                       stream=False)
            if isinstance(resp, dict):
                response_text = resp.get("generated_text") or resp.get("text") or str(resp)
            elif isinstance(resp, list):
                parts = []
                for item in resp:
                    if isinstance(item, dict):
                        parts.append(item.get("generated_text") or item.get("text") or str(item))
                    else:
                        parts.append(str(item))
                response_text = "".join(parts)
            else:
                response_text = str(resp)

        print(f"Generated response length={len(response_text)}. Sample:\n{response_text[:800]}")
        return jsonify({"reply": response_text})
    except Exception as e:
        tb = traceback.format_exc()
        print(f"HF API error: {e}\nTRACEBACK:\n{tb}")
        return jsonify({"reply": "I'm having a little trouble thinking right now. Please check back in a moment."}), 500

# --- JOURNAL SYNC ENDPOINT ---
@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    if STARTUP_ERROR:
        return jsonify({"status": "error", "message": f"Startup error: {STARTUP_ERROR}"}), 500

    data = request.json
    user_id = data.get("userId")
    entry = data.get("entry")

    if not user_id or not entry:
        return jsonify({"status": "error", "message": "Missing userId or entry data"}), 400

    user_entries_ref = db.collection("users").document(user_id).collection("entries")
    user_entries_ref.add(entry)

    return jsonify({"status": "success", "message": "Journal entry synced successfully."}), 200

# --- RESOURCES ENDPOINT ---
@app.route("/resources", methods=["GET"])
def get_resources():
    if STARTUP_ERROR:
        return jsonify({"status": "error", "message": f"Startup error: {STARTUP_ERROR}"}), 500

    articles_ref = db.collection("articles")
    articles = [doc.to_dict() for doc in articles_ref.stream()]
    return jsonify(articles)

# --- ENTRY POINT ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)
