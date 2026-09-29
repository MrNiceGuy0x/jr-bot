"""JR-Bot canonical capability framework (WP-CAP-01)."""
from .model import CapabilityDescriptor
from .validator import CapabilityPolicyError, validate_descriptor
from .loader import CapabilityRegistry
from .executor import CapabilityExecutionError, CapabilityExecutor

__all__ = [
    "CapabilityDescriptor", "CapabilityPolicyError", "validate_descriptor",
    "CapabilityRegistry", "CapabilityExecutionError", "CapabilityExecutor",
]