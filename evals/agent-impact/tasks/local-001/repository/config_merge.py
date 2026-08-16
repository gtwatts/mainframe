"""Nested configuration merge with an intentional fixture defect."""


def resolve_config(defaults: dict, project: dict, user: dict) -> dict:
    """Resolve three configuration layers from lowest to highest precedence."""

    merged = dict(defaults)
    for layer in (project, user):
        for key, value in layer.items():
            if value:
                merged[key] = value
    return merged
