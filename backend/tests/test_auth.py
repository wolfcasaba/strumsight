"""Auth flow: register, login, /me, and the failure paths."""


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_register_returns_token_and_creates_user(client):
    resp = client.post(
        "/auth/register",
        json={"email": "New@Example.com", "password": "sixstrings"},
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    assert token

    # The token works against /me and the email was normalised to lowercase.
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "new@example.com"


def test_register_duplicate_email_conflicts(client):
    body = {"email": "dup@example.com", "password": "sixstrings"}
    assert client.post("/auth/register", json=body).status_code == 201
    resp = client.post("/auth/register", json=body)
    assert resp.status_code == 409


def test_register_rejects_short_password(client):
    resp = client.post(
        "/auth/register", json={"email": "x@example.com", "password": "short"}
    )
    assert resp.status_code == 422


def test_login_success_and_wrong_password(client):
    client.post(
        "/auth/register",
        json={"email": "log@example.com", "password": "sixstrings"},
    )

    ok = client.post(
        "/auth/login",
        json={"email": "log@example.com", "password": "sixstrings"},
    )
    assert ok.status_code == 200
    assert ok.json()["token_type"] == "bearer"

    bad = client.post(
        "/auth/login",
        json={"email": "log@example.com", "password": "wrongpass"},
    )
    assert bad.status_code == 401


def test_login_unknown_email(client):
    resp = client.post(
        "/auth/login",
        json={"email": "ghost@example.com", "password": "whatever1"},
    )
    assert resp.status_code == 401


def test_me_requires_auth(client):
    assert client.get("/auth/me").status_code == 403  # no bearer at all
    bad = client.get("/auth/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert bad.status_code == 401
