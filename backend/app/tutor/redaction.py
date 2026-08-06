"""Backend redaction and content-size guard for tutor output (E04-R23).

Does NOT transmit content telemetry without consent (ADR 0132). The guard
operates on server-side output before it reaches the client; redaction
rules are deterministic and stateless.
"""

from dataclasses import dataclass
from re import Pattern


@dataclass(frozen=True)
class RedactionRule:
    """A single redaction rule: pattern → replacement."""

    pattern: Pattern
    replacement: str


class Redactor:
    """Applies a list of deterministic redaction rules to a text.

    Rules are applied in order; later rules see the output of earlier
    ones. The redaction report indicates whether any rule matched.
    """

    def __init__(self, rules: list[RedactionRule]) -> None:
        self._rules = tuple(rules)

    def redact(self, text: str) -> str:
        """Apply all rules and return the redacted text."""
        result = text
        for rule in self._rules:
            result = rule.pattern.sub(rule.replacement, result)
        return result

    def redact_with_report(self, text: str) -> tuple[str, bool]:
        """Apply all rules and return (redacted_text, was_any_redaction_applied)."""
        result = text
        was_redacted = False
        for rule in self._rules:
            new_result = rule.pattern.sub(rule.replacement, result)
            if new_result != result:
                was_redacted = True
            result = new_result
        return result, was_redacted


class ContentSizeGuard:
    """Rejects content that exceeds a maximum byte size."""

    def __init__(self, max_bytes: int) -> None:
        if max_bytes < 0:
            raise ValueError('max_bytes must be >= 0')
        self._max_bytes = max_bytes

    def check(self, text: str) -> None:
        """Raise ValueError if text exceeds the size limit."""
        size = len(text.encode('utf-8'))
        if size > self._max_bytes:
            raise ValueError(
                f'Content size {size} bytes exceeds size limit of '
                f'{self._max_bytes} bytes'
            )
