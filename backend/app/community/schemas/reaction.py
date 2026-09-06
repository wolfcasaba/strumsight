"""Wire schemas for the Community reaction surface.

A ``services/reaction_service.py`` a Kör 15 óta létezik és tesztelt, és a
modul docstringje ki is mondja, hogy „the wire router is **not** in this
round's ``allowed_paths``" — az a router SOSEM készült el. A hiány a
Flutter-oldalon látszott: a ``CommunityPostRepository.setReaction`` és a
``ReactionBar`` widget végpont nélkül állt.

**A válasz a MŰVELET UTÁNI ÁLLAPOTOT hordozza**, nem csak egy nyugtát. Két
oka van, és mindkettő mért hibaosztályt zár:

1. *Optimista jelölés.* Ha a válasz csak ``{"status": "ok"}`` lenne, a
   ``ReactionBar``-nak magának kellene kitalálnia az új számlálót — és egy
   párhuzamos reagálás után a képernyőn más szám állna, mint a szerveren.
   Ez ugyanaz az osztály, amit a klub-``join`` ``outcome`` mezője zár.

2. *Fajta-váltás.* A ``support`` → ``celebrate`` váltás UPDATE, tehát a
   számláló NEM változik. Egy „+1 / -1" kliensoldali logika itt tévedne;
   a szerver által visszaadott szám nem tévedhet.
"""

from __future__ import annotations

import uuid

from pydantic import BaseModel, ConfigDict, Field

from ..models.reaction import REACTION_KIND_ALLOWLIST


class SetReactionRequest(BaseModel):
    """Törzs a ``PUT /community/posts/{id}/reaction`` híváshoz.

    A megengedett fajtákat a MODELL allowlistája ismeri, az érvényesítést
    pedig a SERVICE végzi (``InvalidReactionKind``). A séma csak hosszt
    korlátoz, hogy az érvényesség EGY helyen dőljön el — ha itt is
    felsorolnánk a fajtákat, két igazságforrás keletkezne, és egy jövőbeli
    bővítés az egyiket ottfelejtené.
    """

    model_config = ConfigDict(extra="forbid")

    kind: str = Field(..., min_length=1, max_length=32)
    idempotency_key: str | None = Field(default=None, max_length=128)


class ReactionStateOut(BaseModel):
    """A poszt reakció-állapota a MŰVELET UTÁN, a néző szemszögéből.

    ``viewer_reaction`` a NÉZŐÉ (``None``, ha nincs), ``reaction_count`` a
    teljes halmazé — ugyanaz a szétválasztás, amit a feed-elem és a klub
    ``my_role`` mezője is visz.
    """

    model_config = ConfigDict(extra="forbid")

    post_public_id: uuid.UUID
    viewer_reaction: str | None = None
    reaction_count: int


#: A felület által elfogadott fajták — a modell allowlistájából, NEM
#: újragépelve. A kliens-oldali szerződés-teszt ezt olvassa.
SUPPORTED_REACTION_KINDS: frozenset[str] = REACTION_KIND_ALLOWLIST


__all__ = [
    "SUPPORTED_REACTION_KINDS",
    "ReactionStateOut",
    "SetReactionRequest",
]
