"""Server-side safety policy for tutor output (E04-R23).

Deterministic, pure mapping from input + flags to a safety verdict. Prompt
injection never raises tool permission; the policy only blocks.
"""

from dataclasses import dataclass, field
from enum import Enum, auto
from re import IGNORECASE
from re import compile as re_compile


class SafetyCategory(Enum):
    """Safety categories ordered by priority (highest first)."""

    PROMPT_INJECTION = auto()
    INVENTED_METRIC = auto()
    CREDENTIAL_REQUEST = auto()
    CAMERA_CLAIM = auto()
    MEDICAL_REFUSAL = auto()
    PAIN_RESPONSE = auto()
    UNSAFE_ACTION = auto()
    COPYRIGHT = auto()
    USAGE_LIMIT = auto()
    REDACTION_REQUIRED = auto()


@dataclass(frozen=True)
class SafetyPolicyRequest:
    """Input to the deterministic safety policy evaluation."""

    output_text: str
    has_injection: bool = False
    has_invented_metric: bool = False
    has_camera_claim: bool = False
    is_rate_limited: bool = False
    is_usage_exceeded: bool = False


@dataclass(frozen=True)
class SafetyVerdict:
    """Deterministic output of the safety policy."""

    blocked_categories: frozenset = field(default_factory=frozenset)

    @property
    def is_allowed(self) -> bool:
        return len(self.blocked_categories) == 0

    def to_dict(self) -> dict:
        return {
            "is_allowed": self.is_allowed,
            "blocked_categories": sorted([c.name for c in self.blocked_categories]),
        }


class SafetyPolicy:
    """Deterministic safety policy for tutor output.

    Maps input (output text + metadata flags) to a safety verdict. All
    triggered categories are collected — the policy returns every match,
    not just the first.
    """

    _PAIN_PATTERN = re_compile(
        r"\b(I\s+feel\s+pain|it\s+hurts|my\s+circuits|I\s+am\s+suffering|"
        r"that\s+hurts|you\s+hurt\s+me|I\s+am\s+in\s+pain)\b",
        IGNORECASE,
    )

    _MEDICAL_PATTERN = re_compile(
        r"\b(diagnos\w+|medical\s+condition|symptom\w*|"
        r"carpal\s+tunnel|tendonitis|arthritis|"
        r"you\s+(have|may\s+have|suffer\s+from)\s+\w+\s+(syndrome|disease|disorder))\b",
        IGNORECASE,
    )

    _COPYRIGHT_PATTERN = re_compile(
        r"\bcopyrighted\b",
        IGNORECASE,
    )

    _CREDENTIAL_PATTERN = re_compile(
        r"\b(enter\s+your\s+(password|api\s+key|credentials|token)|"
        r"provide\s+your\s+(password|api\s+key|credentials|token)|"
        r"what\s+is\s+your\s+(password|api\s+key|credentials)|"
        r"share\s+your\s+(password|credentials|api\s+key|token)|"
        r"your\s+password\s*(is|please)|tell\s+me\s+your\s+password)\b",
        IGNORECASE,
    )

    _UNSAFE_ACTION_PATTERN = re_compile(
        r"\b(cut\s+(the\s+)?(guitar\s+)?strings?\s+with|"
        r"apply\s+(excessive\s+)?force\s+to|"
        r"break\s+the|snap\s+the\s+neck|"
        r"strike\s+(the\s+)?guitar)\b",
        IGNORECASE,
    )

    _REDACTION_PATTERN = re_compile(
        r"\b(api\s*[kK]ey\s*[=:]\s*[a-zA-Z0-9\-_]{8,}|"
        r"secret\s*[=:]\s*[a-zA-Z0-9\-_]{8,}|"
        r"sk-[a-zA-Z0-9]{8,}|"
        r"Bearer\s+[A-Za-z0-9\-._~+/]+=*)\b",
        IGNORECASE,
    )

    def evaluate(self, request: SafetyPolicyRequest) -> SafetyVerdict:
        """Evaluate safety and return a deterministic verdict."""
        blocked: set[SafetyCategory] = set()

        # Flag-driven categories (highest priority first).
        if request.has_injection:
            blocked.add(SafetyCategory.PROMPT_INJECTION)
        if request.has_invented_metric:
            blocked.add(SafetyCategory.INVENTED_METRIC)
        if request.has_camera_claim:
            blocked.add(SafetyCategory.CAMERA_CLAIM)

        # Usage limits.
        if request.is_rate_limited or request.is_usage_exceeded:
            blocked.add(SafetyCategory.USAGE_LIMIT)

        # Text-pattern categories.
        text = request.output_text
        if self._CREDENTIAL_PATTERN.search(text):
            blocked.add(SafetyCategory.CREDENTIAL_REQUEST)
        if self._MEDICAL_PATTERN.search(text):
            blocked.add(SafetyCategory.MEDICAL_REFUSAL)
        if self._PAIN_PATTERN.search(text):
            blocked.add(SafetyCategory.PAIN_RESPONSE)
        if self._UNSAFE_ACTION_PATTERN.search(text):
            blocked.add(SafetyCategory.UNSAFE_ACTION)
        if self._COPYRIGHT_PATTERN.search(text):
            blocked.add(SafetyCategory.COPYRIGHT)
        if self._REDACTION_PATTERN.search(text):
            blocked.add(SafetyCategory.REDACTION_REQUIRED)

        return SafetyVerdict(blocked_categories=frozenset(blocked))
