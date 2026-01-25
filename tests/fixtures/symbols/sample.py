"""Sample Python module for symbol extraction tests."""
import os
from typing import Optional, List

GLOBAL_CONST = "hello"

class BaseModel:
    """Base model class."""

    def __init__(self, name: str) -> None:
        self.name = name

    def validate(self) -> bool:
        """Validate the model."""
        return True

class UserService(BaseModel):
    """User service extending BaseModel."""

    async def get_user(self, user_id: int) -> Optional[dict]:
        """Get user by ID."""
        return None

    def list_users(self) -> List[dict]:
        return []

@app.route("/api/users")
def api_users():
    """API endpoint for users."""
    pass

async def process_data(data: list[str]) -> dict:
    """Process incoming data."""
    return {}

def _private_helper():
    pass
