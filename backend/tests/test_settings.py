"""Settings profile: defaults, partial update, null-locale, validation, auth."""


def test_settings_default_on_new_user(client, auth_headers):
    resp = client.get("/settings", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["theme_mode"] == "system"
    assert data["locale"] is None
    assert data["confidence_threshold"] == 0.45
    assert data["tuning_a4"] == 440


def test_partial_update_only_touches_sent_fields(client, auth_headers):
    resp = client.put(
        "/settings",
        headers=auth_headers,
        json={"theme_mode": "dark", "confidence_threshold": 0.7},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["theme_mode"] == "dark"
    assert data["confidence_threshold"] == 0.7
    # Untouched fields keep their defaults.
    assert data["tuning_a4"] == 440
    assert data["locale"] is None


def test_set_and_clear_locale(client, auth_headers):
    client.put("/settings", headers=auth_headers, json={"locale": "hu"})
    assert client.get("/settings", headers=auth_headers).json()["locale"] == "hu"

    # Explicit null clears it (follow system) — distinct from omitting the key.
    client.put("/settings", headers=auth_headers, json={"locale": None})
    assert client.get("/settings", headers=auth_headers).json()["locale"] is None


def test_update_persists_across_requests(client, auth_headers):
    client.put("/settings", headers=auth_headers, json={"tuning_a4": 432})
    assert client.get("/settings", headers=auth_headers).json()["tuning_a4"] == 432


def test_validation_rejects_out_of_range(client, auth_headers):
    assert (
        client.put(
            "/settings", headers=auth_headers, json={"confidence_threshold": 1.5}
        ).status_code
        == 422
    )
    assert (
        client.put("/settings", headers=auth_headers, json={"tuning_a4": 700}).status_code
        == 422
    )
    assert (
        client.put(
            "/settings", headers=auth_headers, json={"theme_mode": "neon"}
        ).status_code
        == 422
    )
    # Unknown fields are rejected (extra="forbid").
    assert (
        client.put("/settings", headers=auth_headers, json={"nope": 1}).status_code
        == 422
    )


def test_settings_require_auth(client):
    assert client.get("/settings").status_code == 403
    assert client.put("/settings", json={"theme_mode": "dark"}).status_code == 403


def test_settings_are_per_user(client):
    a = client.post(
        "/auth/register", json={"email": "a@ex.com", "password": "sixstrings"}
    ).json()["access_token"]
    b = client.post(
        "/auth/register", json={"email": "b@ex.com", "password": "sixstrings"}
    ).json()["access_token"]

    client.put(
        "/settings",
        headers={"Authorization": f"Bearer {a}"},
        json={"tuning_a4": 432},
    )
    # B is unaffected by A's change.
    b_settings = client.get(
        "/settings", headers={"Authorization": f"Bearer {b}"}
    ).json()
    assert b_settings["tuning_a4"] == 440
