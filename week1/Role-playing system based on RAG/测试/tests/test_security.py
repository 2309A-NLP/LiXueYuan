import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.security import create_access_token, hash_password, verify_password


def test_password_hash_roundtrip() -> None:
    hashed = hash_password("*")
    assert verify_password("*", hashed) is True
    assert verify_password("x", hashed) is False


def test_jwt_contains_sub() -> None:
    token = create_access_token(user_id=42, account="demo")
    assert isinstance(token, str)
    assert len(token) > 10
