import os

from flask import Flask, jsonify

app = Flask(__name__)


@app.after_request
def security_headers(resp):
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Content-Security-Policy"] = "default-src 'none'"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Cache-Control"] = "no-store"
    return resp


@app.get("/")
def index():
    return jsonify(message="Hello from the DevSecOps pipeline", env=os.getenv("APP_ENV", "local"))


@app.get("/health")
def health():
    return jsonify(status="ok")
