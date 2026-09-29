import json
from pathlib import Path
from typing import Dict
from .model import CapabilityDescriptor
from .validator import CapabilityPolicyError, validate_descriptor

class CapabilityRegistry:
    def __init__(self, policy_dir: str, trusted_script_root: str):
        self.policy_dir=Path(policy_dir)
        self.trusted_script_root=trusted_script_root
        self._items: Dict[str, CapabilityDescriptor]={}

    def load(self) -> "CapabilityRegistry":
        items={}
        if not self.policy_dir.is_dir(): raise CapabilityPolicyError("policy directory missing")
        for p in sorted(self.policy_dir.glob("*.json")):
            raw=json.loads(p.read_text(encoding="utf-8"))
            d=validate_descriptor(raw,self.trusted_script_root)
            if d.capability_id in items: raise CapabilityPolicyError("duplicate capability_id")
            items[d.capability_id]=d
        self._items=items
        return self

    def get(self, capability_id: str, revision: int) -> CapabilityDescriptor:
        d=self._items.get(capability_id)
        if d is None: raise CapabilityPolicyError("unknown capability_id")
        if d.revision != revision: raise CapabilityPolicyError("revision mismatch")
        return d