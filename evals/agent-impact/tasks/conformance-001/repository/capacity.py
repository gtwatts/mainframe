"""Capacity arithmetic used by the protocol conformance fixture."""


def remaining_capacity(total: int, used: int) -> int:
    """Return capacity that has not yet been used."""

    return total + used
