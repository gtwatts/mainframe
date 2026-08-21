"""Typed fail-closed errors for the local control-plane kernel."""


class ControlPlaneError(Exception):
    """Base class for expected control-plane failures."""

    code = "control_plane_error"


class ValidationError(ControlPlaneError):
    code = "validation_error"


class NotFound(ControlPlaneError):
    code = "not_found"


class AlreadyExists(ControlPlaneError):
    code = "already_exists"


class InvalidTransition(ControlPlaneError):
    code = "invalid_transition"


class BindingMismatch(ControlPlaneError):
    code = "binding_mismatch"


class ApprovalExpired(ControlPlaneError):
    code = "approval_expired"


class ApprovalConsumed(ControlPlaneError):
    code = "approval_consumed"


class ApprovalAuthorityUnavailable(ControlPlaneError):
    code = "approval_authority_unavailable"


class ExecutionDenied(ControlPlaneError):
    code = "execution_denied"


class ExecutorUnavailable(ControlPlaneError):
    code = "executor_unavailable"


class EvaluatorUnavailable(ControlPlaneError):
    code = "evaluator_unavailable"


class LedgerCorruption(ControlPlaneError):
    code = "ledger_corruption"


class LedgerIOError(ControlPlaneError):
    code = "ledger_io_error"


class DurabilityUnavailable(LedgerIOError):
    code = "durability_unavailable"


class RegistryCorruption(ControlPlaneError):
    code = "registry_corruption"
