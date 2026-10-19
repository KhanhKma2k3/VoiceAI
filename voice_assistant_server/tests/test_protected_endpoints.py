from fastapi.testclient import TestClient

from main import app
import routes.ai_chat as ai_chat_module

client = TestClient(app)


def _register_and_get_token(username: str) -> str:
    resp = client.post("/register", json={"username": username, "password": "matkhau123"})
    assert resp.status_code == 200
    return resp.json()["access_token"]


def test_chat_requires_authentication():
    # Đây chính là điều mà bản trước bị THIẾU: gọi /chat mà không có token
    # phải bị chặn 401, không được phép đi thẳng vào Gemini.
    resp = client.post("/chat", json={"message": "xin chào"})
    assert resp.status_code == 401


def test_chat_works_with_valid_token(monkeypatch):
    token = _register_and_get_token("user_test_chat")

    # Không gọi Gemini thật trong test -> monkeypatch trả lời giả.
    monkeypatch.setattr(ai_chat_module, "ask_gemini", lambda prompt: "phản hồi giả lập")

    resp = client.post(
        "/chat",
        json={"message": "xin chào"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["bot_reply"] == "phản hồi giả lập"


def test_chat_rejects_invalid_token():
    resp = client.post(
        "/chat",
        json={"message": "xin chào"},
        headers={"Authorization": "Bearer token-khong-hop-le"},
    )
    assert resp.status_code == 401


def test_history_only_returns_own_conversations(monkeypatch):
    monkeypatch.setattr(ai_chat_module, "ask_gemini", lambda prompt: "trả lời A")
    token_a = _register_and_get_token("user_test_history_a")
    token_b = _register_and_get_token("user_test_history_b")

    client.post(
        "/chat",
        json={"message": "câu hỏi của A"},
        headers={"Authorization": f"Bearer {token_a}"},
    )

    resp_a = client.get("/history", headers={"Authorization": f"Bearer {token_a}"})
    resp_b = client.get("/history", headers={"Authorization": f"Bearer {token_b}"})

    assert resp_a.status_code == 200
    assert resp_b.status_code == 200
    assert any(item["user_message"] == "câu hỏi của A" for item in resp_a.json())
    # User B không được thấy hội thoại của user A (lỗ hổng rò rỉ dữ liệu đã sửa).
    assert all(item["user_message"] != "câu hỏi của A" for item in resp_b.json())
