from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_register_and_login_flow():
    # Đăng ký user mới
    resp = client.post("/register", json={"username": "user_test_1", "password": "matkhau123"})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert data["username"] == "user_test_1"

    # Đăng ký trùng username phải báo lỗi
    resp_dup = client.post("/register", json={"username": "user_test_1", "password": "khac123"})
    assert resp_dup.status_code == 400

    # Đăng nhập đúng mật khẩu
    resp_login = client.post("/login", json={"username": "user_test_1", "password": "matkhau123"})
    assert resp_login.status_code == 200
    assert "access_token" in resp_login.json()

    # Đăng nhập sai mật khẩu
    resp_wrong = client.post("/login", json={"username": "user_test_1", "password": "sai_roi"})
    assert resp_wrong.status_code == 400


def test_register_with_email_login_by_email_and_me():
    resp = client.post("/register", json={"username": "mail_user", "password": "matkhau123", "email": "Mail.User@Gmail.com"})
    assert resp.status_code == 200
    assert resp.json()["email"] == "mail.user@gmail.com"

    # Email trùng bị từ chối
    dup = client.post("/register", json={"username": "other", "password": "matkhau123", "email": "mail.user@gmail.com"})
    assert dup.status_code == 400

    # Đăng nhập bằng email
    login = client.post("/login", json={"username": "mail.user@gmail.com", "password": "matkhau123"})
    assert login.status_code == 200
    token = login.json()["access_token"]

    me = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["username"] == "mail_user"
    assert me.json()["email"] == "mail.user@gmail.com"


def test_forgot_and_reset_password(monkeypatch):
    sent = {}
    import routes.auth as auth_routes
    monkeypatch.setattr(auth_routes, "send_reset_code", lambda email, code: sent.update(email=email, code=code) or True)

    client.post("/register", json={"username": "reset_user", "password": "matkhau123", "email": "reset@example.com"})

    # Email không tồn tại vẫn trả 200 (không lộ thông tin) nhưng không gửi mã
    assert client.post("/forgot-password", json={"email": "nobody@example.com"}).status_code == 200
    assert "code" not in sent

    assert client.post("/forgot-password", json={"email": "reset@example.com"}).status_code == 200
    assert sent["email"] == "reset@example.com"

    # Sai mã
    bad = client.post("/reset-password", json={"email": "reset@example.com", "code": "000000x", "new_password": "moi12345"})
    assert bad.status_code == 400

    # Đúng mã
    ok = client.post("/reset-password", json={"email": "reset@example.com", "code": sent["code"], "new_password": "moi12345"})
    assert ok.status_code == 200
    assert client.post("/login", json={"username": "reset_user", "password": "moi12345"}).status_code == 200
    assert client.post("/login", json={"username": "reset_user", "password": "matkhau123"}).status_code == 400

    # Mã chỉ dùng được 1 lần
    again = client.post("/reset-password", json={"email": "reset@example.com", "code": sent["code"], "new_password": "khac12345"})
    assert again.status_code == 400


def test_login_unknown_email_and_validation():
    assert client.post("/login", json={"username": "ghost@example.com", "password": "abcdef"}).status_code == 400
    # Tên tài khoản chứa '@' hoặc quá ngắn bị từ chối; mật khẩu quá ngắn bị từ chối.
    assert client.post("/register", json={"username": "a@b", "password": "matkhau123"}).status_code == 400
    assert client.post("/register", json={"username": "ab", "password": "matkhau123"}).status_code == 400
    assert client.post("/register", json={"username": "valid_user_x", "password": "123"}).status_code == 400
    assert client.post("/register", json={"username": "valid_user_x", "password": "matkhau123", "email": "khong-hop-le"}).status_code == 400


def test_forgot_password_cooldown_and_failed_send(monkeypatch):
    import routes.auth as auth_routes

    client.post("/register", json={"username": "cool_user", "password": "matkhau123", "email": "cool@example.com"})

    # Gửi mail thất bại -> 503 và có thể thử lại ngay (không bị cooldown)
    monkeypatch.setattr(auth_routes, "send_reset_code", lambda e, c: False)
    assert client.post("/forgot-password", json={"email": "cool@example.com"}).status_code == 503

    sent = {}
    monkeypatch.setattr(auth_routes, "send_reset_code", lambda e, c: sent.update(code=c) or True)
    assert client.post("/forgot-password", json={"email": "cool@example.com"}).status_code == 200
    # Yêu cầu lại ngay -> bị chặn bởi cooldown
    assert client.post("/forgot-password", json={"email": "cool@example.com"}).status_code == 429


def test_reset_code_locks_after_too_many_wrong_attempts(monkeypatch):
    import routes.auth as auth_routes

    sent = {}
    monkeypatch.setattr(auth_routes, "send_reset_code", lambda e, c: sent.update(code=c) or True)
    client.post("/register", json={"username": "lock_user", "password": "matkhau123", "email": "lock@example.com"})
    client.post("/forgot-password", json={"email": "lock@example.com"})

    for _ in range(auth_routes.RESET_MAX_ATTEMPTS):
        r = client.post("/reset-password", json={"email": "lock@example.com", "code": "999999", "new_password": "moi12345"})
        assert r.status_code == 400

    # Dù nhập ĐÚNG mã, mã đã bị khóa vì sai quá nhiều lần
    r = client.post("/reset-password", json={"email": "lock@example.com", "code": sent["code"], "new_password": "moi12345"})
    assert r.status_code == 400
    assert client.post("/login", json={"username": "lock_user", "password": "matkhau123"}).status_code == 200


def test_google_login_requires_config_and_valid_token(monkeypatch):
    import routes.auth as auth_routes
    from services.auth_service import GoogleAuthError

    from config import settings

    # Chưa cấu hình GOOGLE_CLIENT_ID -> 503 (ép rỗng để test không phụ thuộc .env thật)
    monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", "")
    assert client.post("/auth/google", json={"id_token": "x"}).status_code == 503

    def bad(_):
        raise GoogleAuthError("sai")
    monkeypatch.setattr(auth_routes, "verify_google_id_token", bad)
    assert client.post("/auth/google", json={"id_token": "x"}).status_code == 401

    info = {"sub": "g-123", "email": "Nguoi.Dung@gmail.com", "name": "Người Dùng", "email_verified": True}
    monkeypatch.setattr(auth_routes, "verify_google_id_token", lambda _: info)
    first = client.post("/auth/google", json={"id_token": "ok"})
    assert first.status_code == 200
    assert first.json()["email"] == "nguoi.dung@gmail.com"
    # Đăng nhập lần 2 dùng lại đúng tài khoản
    second = client.post("/auth/google", json={"id_token": "ok"})
    assert second.json()["username"] == first.json()["username"]
