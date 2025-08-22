# backend/app.py (REVERTED TO STABLE SECTION 2 VERSION)

from flask import Flask, request, jsonify
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client(project="sahara-wellness-prototype")

@app.route("/chat", methods=["POST"])
def handle_chat():
    user_message = request.json.get("message", "")
    print(f"Received (mock) chat message: {user_message}")
    # THIS IS THE KEY: We return a reliable, hardcoded string. NO GEMINI CALL.
    return jsonify({"reply": "Thank you for sharing that with me. I am here to listen."})

@app.route("/journal/sync", methods=["POST"])
def handle_journal_sync():
    data = request.json
    user_id = data.get('userId')
    entry = data.get('entry')
    if not user_id or not entry:
        return jsonify({"status": "error", "message": "Missing data"}), 400
    user_entries_ref = db.collection('users').document(user_id).collection('entries')
    user_entries_ref.add(entry)
    return jsonify({"status": "success"}), 200

@app.route("/resources", methods=["GET"])
def get_resources():
    articles_ref = db.collection('articles')
    articles = [doc.to_dict() for doc in articles_ref.stream()]
    return jsonify(articles)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)